<#
.SYNOPSIS
  Verify a deployed report by what it actually produces -- HTTP success, content
  (row count / expected text in the CSV export), and an optional visual baseline.

.DESCRIPTION
  A 200 + %PDF- only proves the report ran, not that it has the right content.
  This runs the report server-side and asserts:
    * the chosen format returns 200 with the right magic bytes + non-trivial size;
    * (optional) the CSV export has >= -MinRows data rows and contains every
      -Contains string;
    * (optional) page 1 rasterized matches a committed -Baseline PNG within
      -MaxPixelDiff (mean abs pixel difference). With -UpdateBaseline (or a
      missing baseline) the current render is saved as the baseline.
  Throws on any failed assertion; prints a PASS/FAIL line per check.

.PARAMETER Uri
  Report repository URI, e.g. /reports/foodmart/foodmart_sales_by_family.

.PARAMETER Params
  Hashtable of report parameters for the run, e.g. @{ family = "Drink" }.

.EXAMPLE
  .\verify_report.ps1 -Uri /reports/foodmart/foodmart_top_categories `
      -MinRows 10 -Contains "Vegetables","Snack Foods" `
      -Baseline baselines\top_categories.png
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Uri,
    [string]$Format = "pdf",
    [int]$MinRows = 0,
    [string[]]$Contains,
    [hashtable]$Params,
    [string]$Baseline,
    [double]$MaxPixelDiff = 2.0,
    [switch]$UpdateBaseline,
    [string]$OutDir = "out\verify",
    [string]$ServerUrl,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")
$jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password
$auth = "$($jrs.User):$($jrs.Password)"
if (-not $Uri.StartsWith("/")) { $Uri = "/$Uri" }
New-Item -ItemType Directory -Force $OutDir | Out-Null
$rname = ($Uri -split "/")[-1]

# query string from -Params
$qs = ""
if ($Params) {
    $pairs = foreach ($k in $Params.Keys) { "$k=" + [uri]::EscapeDataString("$($Params[$k])") }
    $qs = "?" + ($pairs -join "&")
}

$fails = @()
$base = "$($jrs.ServerUrl)/rest_v2/reports$Uri"
$magic = @{ pdf = "%PDF-"; xlsx = "PK"; docx = "PK"; pptx = "PK"; ods = "PK"; odt = "PK" }

# --- 1. run in the requested format -------------------------------------------
$outFile = Join-Path $OutDir "$rname.$Format"
$code = & curl.exe -s -o $outFile -w "%{http_code}" -u $auth "$base.$Format$qs"
$size = if (Test-Path $outFile) { (Get-Item $outFile).Length } else { 0 }
$head = if (Test-Path $outFile) { (Get-Content $outFile -TotalCount 1 -ErrorAction SilentlyContinue) } else { "" }
$wantMagic = $magic[$Format]
$okRun = ("$code".Trim() -eq "200") -and ($size -gt 800) -and ((-not $wantMagic) -or ("$head" -like "$wantMagic*"))
if ($okRun) { Write-Host "PASS run     $Format http=$code size=$size" }
else { Write-Host "FAIL run     $Format http=$code size=$size"; $fails += "run" }

# --- 2. content assertions via CSV --------------------------------------------
if ($MinRows -gt 0 -or $Contains) {
    $csv = Join-Path $OutDir "$rname.csv"
    $cc = & curl.exe -s -o $csv -w "%{http_code}" -u $auth "$base.csv$qs"
    $text = if (Test-Path $csv) { Get-Content $csv -Raw } else { "" }
    # data rows: non-empty lines that carry a value, minus the title/header lines
    $lines = @(Get-Content $csv -ErrorAction SilentlyContinue | Where-Object { $_ -match "\S" })
    $dataRows = [Math]::Max(0, $lines.Count - 2)
    if ($MinRows -gt 0) {
        if ($dataRows -ge $MinRows) { Write-Host "PASS rows     $dataRows >= $MinRows" }
        else { Write-Host "FAIL rows     $dataRows < $MinRows"; $fails += "rows" }
    }
    foreach ($needle in ($Contains | Where-Object { $_ })) {
        if ($text -like "*$needle*") { Write-Host "PASS contains '$needle'" }
        else { Write-Host "FAIL contains '$needle'"; $fails += "contains:$needle" }
    }
}

# --- 3. visual baseline -------------------------------------------------------
if ($Baseline) {
    $pdf = Join-Path $OutDir "$rname.pdf"
    if ($Format -ne "pdf" -or -not (Test-Path $pdf)) {
        & curl.exe -s -o $pdf -u $auth "$base.pdf$qs" | Out-Null
    }
    $png = Join-Path $OutDir "$rname.page1.png"
    $args = @("$PSScriptRoot\pdf_verify.py", "--pdf", $pdf, "--png", $png,
              "--baseline", $Baseline, "--max-diff", "$MaxPixelDiff")
    if ($UpdateBaseline) { $args += "--update" }
    # run under Continue: a stray Python warning on stderr would otherwise abort
    # this Stop-mode script even on a clean exit. Judge by the exit code.
    & { $ErrorActionPreference = "Continue"; $script:vout = (& python @args 2>&1 | Out-String).Trim() }
    $vcode = $LASTEXITCODE
    if ($vcode -eq 0) { Write-Host "PASS visual   $vout" }
    else { Write-Host "FAIL visual   $vout"; $fails += "visual" }
}

Write-Host ""
if ($fails.Count) { throw "verify FAILED for $Uri : $($fails -join ', ')" }
Write-Host "OK: $Uri verified"
