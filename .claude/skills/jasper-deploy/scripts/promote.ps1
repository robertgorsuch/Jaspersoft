<#
.SYNOPSIS
  Promote a repository resource (dashboard, report, folder, datasource, ...) from
  one JasperReports Server to another by export + import.

.DESCRIPTION
  Exports -Uri from the SOURCE server to a local archive, then imports it into the
  TARGET server. Because the archive is the server's own export format, the
  resource lands at the same URI and renders identically -- the supported
  dev->prod promotion path. Export a folder URI to promote a whole app at once.

  Source credentials default to the skill's jrs.config.json (or -From*/env);
  TARGET credentials are required (-To*).

.PARAMETER Uri
  Repository URI to promote, e.g. /reports/foodmart/foodmart_kpi_dashboard_auto
  (a folder promotes everything under it).

.PARAMETER ToServerUrl / ToUser / ToPassword
  Target server. Required (the whole point is a different server).

.PARAMETER Archive
  Where to write the intermediate .zip (default backups\promote_<name>.zip).

.EXAMPLE
  .\promote.ps1 -Uri /reports/geocoder/sales_dashboard `
      -ToServerUrl https://prod:8443/jasperserver-pro -ToUser admin -ToPassword secret
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Uri,
    [Parameter(Mandatory = $true)][string]$ToServerUrl,
    [Parameter(Mandatory = $true)][string]$ToUser,
    [Parameter(Mandatory = $true)][string]$ToPassword,
    [string]$FromServerUrl,
    [string]$FromUser,
    [string]$FromPassword,
    [string]$Archive,
    [bool]$Update = $true
)

$ErrorActionPreference = "Stop"
if (-not $Uri.StartsWith("/")) { $Uri = "/$Uri" }
$leaf = ($Uri -split "/")[-1]
if (-not $Archive) { $Archive = "backups\promote_$leaf.zip" }

Write-Host "=== export $Uri from source ==="
& (Join-Path $PSScriptRoot "export_resource.ps1") -Uri $Uri -Out $Archive `
    -ServerUrl $FromServerUrl -User $FromUser -Password $FromPassword

Write-Host "=== import into target $ToServerUrl ==="
& (Join-Path $PSScriptRoot "import_resource.ps1") -Zip $Archive -Update $Update `
    -ServerUrl $ToServerUrl -User $ToUser -Password $ToPassword

Write-Host "OK: promoted $Uri -> $ToServerUrl (archive: $Archive)"
