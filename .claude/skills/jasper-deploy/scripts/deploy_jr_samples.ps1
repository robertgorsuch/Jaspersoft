<#
.SYNOPSIS
  Bulk-deploy a tree of .jrxml files to JasperReports Server and verify each by
  running it to PDF. Built for the JasperReports Library demo samples, but works
  on any folder of jrxml.

.DESCRIPTION
  Walks -SamplesDir for *.jrxml. A report is "standalone" if its jrxml has no
  <query> element — it runs on an empty data source, so it can be deployed and
  run without external data. Standalone reports are deployed (no data source)
  under -TargetRoot and run to PDF to confirm they render. Reports WITH a query
  need a data source and are listed as skipped (deploy them separately with
  deploy_report.ps1 -DataSourceUri).

  Server URL/credentials resolve via deploy_report.ps1 (params -> env -> config).
  Results are written to -CsvOut.

.EXAMPLE
  .\deploy_jr_samples.ps1
  .\deploy_jr_samples.ps1 -SamplesDir C:\path\to\samples -IncludeQueryReports
#>
[CmdletBinding()]
param(
    [string]$SamplesDir = "C:\Users\rgorsuch\jasperreports-7.0.6\demo\samples",
    [string]$TargetRoot = "/reports/jr_samples",
    [string]$CsvOut = "C:\Users\rgorsuch\tx-geocoder\output\jr_samples_results.csv",
    [switch]$IncludeQueryReports,   # also deploy (but not expect to run) query-based reports
    [string]$DataSourceUri,         # attach to query-based reports so they can run
    [int]$Limit = 0,                # 0 = no limit
    [string]$ServerUrl, [string]$User, [string]$Password
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")
$deploy = Join-Path $PSScriptRoot "deploy_report.ps1"
# one config resolution (param -> env -> jrs.config.json) used for BOTH the
# deploy substep and the run-to-PDF step, so they can't disagree.
$jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password
$cred = "$($jrs.User):$($jrs.Password)"
$logDir = Join-Path (Split-Path $CsvOut -Parent) "jr_samples_logs"
New-Item -ItemType Directory -Force $logDir | Out-Null

function Sanitize([string]$s) { return ($s -replace '[^A-Za-z0-9_]', '_') }

$jrxmls = Get-ChildItem -Path $SamplesDir -Recurse -Filter *.jrxml
if ($Limit -gt 0) { $jrxmls = $jrxmls | Select-Object -First $Limit }

$results = New-Object System.Collections.Generic.List[object]
$n = 0
foreach ($f in $jrxmls) {
    $n++
    $content = Get-Content $f.FullName -Raw
    $hasQuery = $content -match '<query(String)?[ >]'
    $sample = Split-Path (Split-Path (Split-Path $f.FullName -Parent) -Parent) -Leaf
    $base = [IO.Path]::GetFileNameWithoutExtension($f.Name)
    $id = Sanitize("$sample`_$base")
    $uri = "$TargetRoot/$id"
    $row = [ordered]@{ sample = $sample; report = $base; hasQuery = $hasQuery; uri = $uri; deploy = ""; run = ""; log = "" }

    if ($hasQuery -and -not $IncludeQueryReports -and -not $DataSourceUri) {
        $row.deploy = "skipped"; $row.run = "needs-datasource"
        $results.Add([pscustomobject]$row); continue
    }

    # deploy (attach a data source for query-based reports when provided)
    $deployArgs = @{ Jrxml = $f.FullName; TargetUri = $uri; Label = "$sample / $base"; Overwrite = $true
                     ServerUrl = $jrs.ServerUrl; User = $jrs.User; Password = $jrs.Password }
    if ($hasQuery -and $DataSourceUri) { $deployArgs.DataSourceUri = $DataSourceUri }
    try {
        # capture all streams (incl. Write-Host) so a failure's reason is preserved
        $out = & $deploy @deployArgs *>&1
        $row.deploy = "ok"
    } catch {
        $logFile = Join-Path $logDir "$id.log"
        ($out, $_.Exception.Message) | Out-String | Set-Content $logFile -Encoding utf8
        $row.deploy = "FAIL"; $row.run = "-"; $row.log = $logFile
        $results.Add([pscustomobject]$row); continue
    }

    if ($hasQuery -and -not $DataSourceUri) { $row.run = "needs-datasource"; $results.Add([pscustomobject]$row); continue }

    # run to PDF
    $tmp = [IO.Path]::GetTempFileName()
    $code = & curl.exe -s -o $tmp -w "%{http_code}" -u $cred "$($jrs.ServerUrl)/rest_v2/reports$uri.pdf"
    $sig = ""
    if (Test-Path $tmp) { $sig = [IO.File]::ReadAllBytes($tmp)[0..4] -join ','; Remove-Item $tmp -ErrorAction SilentlyContinue }
    $row.run = if ($code -eq "200" -and $sig -match '^37,80,68,70') { "ok" } else { "FAIL($code)" }
    $results.Add([pscustomobject]$row)
    Write-Host ("[{0}/{1}] {2,-28} deploy={3} run={4}" -f $n,$jrxmls.Count,$id,$row.deploy,$row.run)
}

$results | Export-Csv -Path $CsvOut -NoTypeInformation -Encoding utf8

# summary
$dep = ($results | Where-Object deploy -eq 'ok').Count
$ran = ($results | Where-Object run -eq 'ok').Count
$skip = ($results | Where-Object deploy -eq 'skipped').Count
$fail = ($results | Where-Object { $_.deploy -eq 'FAIL' -or $_.run -like 'FAIL*' }).Count
Write-Host ""
Write-Host "==== SUMMARY ===="
Write-Host "total jrxml      : $($results.Count)"
Write-Host "deployed         : $dep"
Write-Host "ran to PDF (ok)  : $ran"
Write-Host "skipped (data)   : $skip"
Write-Host "failed           : $fail"
Write-Host "details          : $CsvOut"
