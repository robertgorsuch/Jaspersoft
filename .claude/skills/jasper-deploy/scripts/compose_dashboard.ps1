<#
.SYNOPSIS
  Compose a JasperReports Server dashboard from a manifest and deploy it -- no
  designer needed.

.DESCRIPTION
  JRS 10 dashboards cannot be created by PUTting a model to /rest_v2/resources
  (the server stores it but renders it blank). The supported path is import of
  the designer's own export archive. This script reproduces that archive
  programmatically:

    1. Export the already-deployed dashlet reports named in the manifest -- this
       yields a real, importable envelope (reportUnit descriptors + their jrxml,
       the datasource, the folder chain, a valid index.xml).
    2. Synthesize the dashboard descriptor + the three companion files
       (components.data / layout / wiring.data) from the manifest, via
       gen_dashboard.py. (The model shape was reverse-engineered from a real
       designer export; every field matches.)
    3. Inject the dashboard into the exported envelope, point index.xml's
       repositoryResources at the dashboard, re-zip (forward-slash entries so the
       Java importer reads them), and import.

  Because the resulting archive is structurally identical to a designer export,
  the imported dashboard renders correctly (unlike a raw resource PUT).

  The dashlet reports MUST already be deployed (use build_dashlets.ps1 first).
  Credentials resolve via _jrs_common.ps1.

.PARAMETER Manifest
  Dashboard manifest JSON: { folder, name, label, dashlets:[{resource,label,
  x,y,width,height}, ...] }. See build_dashlets.ps1 for the combined manifest
  that also builds the dashlets.

.PARAMETER AutoGrid
  Auto-place any dashlet missing x/y/width/height on a two-column 40-wide grid.

.PARAMETER WorkDir
  Scratch directory for the intermediate archives (default out\dash_build).

.EXAMPLE
  .\compose_dashboard.ps1 -Manifest report\foodmart\dashboard.json -AutoGrid
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Manifest,
    [switch]$AutoGrid,
    [string]$WorkDir = "out\dash_build",
    [int]$TimeoutSec = 120,
    [string]$ServerUrl,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not (Test-Path $Manifest)) { throw "manifest not found: $Manifest" }
$jrs  = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password
$auth = "$($jrs.User):$($jrs.Password)"

# --- read manifest (tolerate a UTF-8 BOM) -------------------------------------
$m = (Get-Content $Manifest -Raw) -replace "^\xEF\xBB\xBF", "" | ConvertFrom-Json
$folder = $m.folder.TrimEnd("/")
$name   = $m.name
$dashUri = "$folder/$name"
# only report tiles need exporting (text/image tiles carry no repository report)
$reportUris = @($m.dashlets | Where-Object { -not $_.kind -or $_.kind -eq "report" } |
    ForEach-Object { if ($_.resource) { $_.resource } else { "$folder/$($_.name)" } } |
    Select-Object -Unique)
if (-not $reportUris) { throw "manifest has no report dashlets to export" }
Write-Host "composing dashboard $dashUri from $($reportUris.Count) dashlet(s)"

# fresh workspace
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$baseZip = Join-Path $WorkDir "base.zip"
$genZip  = Join-Path $WorkDir "gen.zip"
$tree    = Join-Path $WorkDir "tree"
$finalZip = Join-Path $WorkDir "$name.zip"

# --- 1. export the dashlet reports -> real importable envelope ----------------
$body = @{ uris = $reportUris; parameters = @("repository-permissions") } | ConvertTo-Json -Compress
$reqFile = [IO.Path]::GetTempFileName()
$body | Set-Content -Path $reqFile -Encoding utf8
try {
    $resp = & curl.exe -s -S -u $auth -X POST -H "Content-Type: application/json" `
        -H "Accept: application/json" --data-binary "@$reqFile" "$($jrs.ServerUrl)/rest_v2/export"
} finally { Remove-Item $reqFile -ErrorAction SilentlyContinue }
$eid = ($resp | ConvertFrom-Json).id
if (-not $eid) { throw "export request failed: $resp" }
$deadline = (Get-Date).AddSeconds($TimeoutSec)
do {
    Start-Sleep -Milliseconds 800
    $phase = (& curl.exe -s -u $auth -H "Accept: application/json" "$($jrs.ServerUrl)/rest_v2/export/$eid/state" | ConvertFrom-Json).phase
    if ($phase -eq "failed") { throw "export failed for dashlet reports" }
} while ($phase -ne "finished" -and (Get-Date) -lt $deadline)
if ($phase -ne "finished") { throw "export timed out (phase=$phase)" }
$code = & curl.exe -s -o $baseZip -w "%{http_code}" -u $auth -H "Accept: application/zip" "$($jrs.ServerUrl)/rest_v2/export/$eid/exportFile"
if ("$code".Trim() -ne "200") { throw "export download failed (HTTP $code)" }
Write-Host "  exported envelope: $((Get-Item $baseZip).Length) bytes"

# --- 2. synthesize the dashboard descriptor + companion files -----------------
$genArgs = @("$PSScriptRoot\gen_dashboard.py", "--manifest", $Manifest, "--out", $genZip)
if ($AutoGrid) { $genArgs += "--auto-grid" }
& python @genArgs | Write-Host
if ($LASTEXITCODE -ne 0) { throw "gen_dashboard.py failed" }

# --- 3. inject dashboard into the envelope ------------------------------------
[System.IO.Compression.ZipFile]::ExtractToDirectory((Resolve-Path $baseZip), (Join-Path (Get-Location) $tree))
$genX = Join-Path $WorkDir "gen_x"
[System.IO.Compression.ZipFile]::ExtractToDirectory((Resolve-Path $genZip), (Join-Path (Get-Location) $genX))

$rel = "resources$folder"
$dst = Join-Path $tree $rel
New-Item -ItemType Directory -Force $dst | Out-Null
Copy-Item (Join-Path $genX "$rel\$name.xml") $dst -Force
Copy-Item (Join-Path $genX "$rel\${name}_files") $dst -Recurse -Force

# point index.xml's repositoryResources at the dashboard (reports stay as deps)
$indexPath = Join-Path $tree "index.xml"
$idx = Get-Content $indexPath -Raw
$idx = [regex]::Replace($idx, '<module id="repositoryResources">.*?</module>',
    "<module id=`"repositoryResources`"><resource>$dashUri</resource></module>")
Set-Content $indexPath -Value $idx -Encoding utf8 -NoNewline

# --- 4. re-zip with forward-slash entries (Java importer requires it) ---------
if (Test-Path $finalZip) { Remove-Item $finalZip -Force }
$treeFull = (Resolve-Path $tree).Path
& python -c @"
import zipfile, os, sys
root = sys.argv[1]
with zipfile.ZipFile(sys.argv[2], 'w', zipfile.ZIP_DEFLATED) as z:
    for d, _, fs in os.walk(root):
        for f in fs:
            full = os.path.join(d, f)
            z.write(full, os.path.relpath(full, root).replace(os.sep, '/'))
"@ $treeFull $finalZip
if ($LASTEXITCODE -ne 0) { throw "re-zip failed" }

# --- 5. import & verify -------------------------------------------------------
& (Join-Path $PSScriptRoot "import_resource.ps1") -Zip $finalZip `
    -ServerUrl $jrs.ServerUrl -User $jrs.User -Password $jrs.Password | Write-Host

$check = & curl.exe -s -u $auth -H "Accept: application/json" "$($jrs.ServerUrl)/rest_v2/resources$dashUri"
if ($check -match "resource.not.found") { throw "import reported success but $dashUri was not created" }
$n = ($check | ConvertFrom-Json).resources.Count
$enc = [uri]::EscapeDataString($dashUri)
Write-Host ""
Write-Host "OK: composed dashboard $dashUri ($($reportUris.Count) dashlets, $n model resources)"
Write-Host "    view: $($jrs.ServerUrl)/dashboard/viewer.html#$enc"
