<#
.SYNOPSIS
  Delete a dashboard and (optionally) the report dashlets it owns, in the order
  JRS requires.

.DESCRIPTION
  A report that is a dashlet of a dashboard is modification/delete-locked
  (403 resource.in.use) while the dashboard exists. This deletes the dashboard
  first, then -- with -IncludeReports -- each report tile it referenced (plus the
  "<report>_controls" folder that deploy_report.ps1 -Control creates). A report
  still referenced by ANOTHER dashboard returns 403 and is skipped with a note,
  so a shared report is never half-deleted.

.PARAMETER Uri
  Dashboard repository URI, e.g. /reports/foodmart/foodmart_kpi_dashboard_auto.

.PARAMETER IncludeReports
  Also delete the report dashlets (and their _controls folders).

.PARAMETER DryRun
  Print what would be deleted without deleting anything.

.EXAMPLE
  .\teardown_dashboard.ps1 -Uri /reports/foodmart/foodmart_kpi_dashboard_auto -IncludeReports
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Uri,
    [switch]$IncludeReports,
    [switch]$DryRun,
    [string]$ServerUrl,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")
$jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password
if (-not $Uri.StartsWith("/")) { $Uri = "/$Uri" }

$cur = Invoke-JrsGet -Jrs $jrs -Uri $Uri
if ($cur.Code -notmatch '^2\d\d$') { Write-Host "dashboard $Uri not found ($($cur.Code)); nothing to do"; return }
$model = $cur.Body | ConvertFrom-Json
$reportUris = @($model.resources | Where-Object { $_.type -eq "reportUnit" } |
    ForEach-Object { $_.resource.resourceReference.uri } | Where-Object { $_ } | Select-Object -Unique)
Write-Host "dashboard $Uri references $($reportUris.Count) report tile(s)"

if ($DryRun) {
    Write-Host "[dry-run] would DELETE dashboard $Uri"
    if ($IncludeReports) { $reportUris | ForEach-Object { Write-Host "[dry-run] would DELETE report $_ (+ ${_}_controls)" } }
    return
}

# 1. dashboard first (frees the report locks)
$dc = Invoke-JrsDelete -Jrs $jrs -Uri $Uri
Write-Host "DELETE $Uri -> $dc"
if ($dc -notmatch '^(2\d\d|404)$') { throw "could not delete dashboard $Uri ($dc)" }

# 2. report tiles + their control folders
if ($IncludeReports) {
    foreach ($r in $reportUris) {
        $rc = Invoke-JrsDelete -Jrs $jrs -Uri $r
        if ($rc -eq "403") { Write-Host "skip   $r (still in use by another dashboard)" }
        else { Write-Host "DELETE $r -> $rc" }
        $ctl = "${r}_controls"
        $cc = Invoke-JrsDelete -Jrs $jrs -Uri $ctl
        if ($cc -match '^2\d\d$') { Write-Host "DELETE $ctl -> $cc" }
    }
}
Write-Host "OK: torn down $Uri"
