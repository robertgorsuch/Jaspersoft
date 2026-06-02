<#
.SYNOPSIS
  Export a JasperReports Server resource (dashboard, report, folder, datasource,
  ...) to a local .zip via the REST v2 export service.

.DESCRIPTION
  Dashboards (and other composite resources) are best moved as faithful export
  archives rather than hand-composed descriptors -- the archive is exactly what
  the JRS designer produced, so it re-imports and renders identically. This is
  the supported way to version-control a dashboard and promote it across servers.

  Flow: POST /rest_v2/export {uris,parameters} -> {id}; poll
  GET /rest_v2/export/{id}/state until phase=finished; download
  GET /rest_v2/export/{id}/exportFile -> -Out.

  Server URL and credentials resolve via _jrs_common.ps1 (param -> env
  JRS_URL/JRS_USER/JRS_PASS -> jrs.config.json).

.PARAMETER Uri
  Repository URI to export, e.g. /public/Samples/Dashboards/1._Supermart_Dashboard
  (a folder exports everything under it).

.PARAMETER Out
  Local path for the .zip archive.

.PARAMETER Parameters
  Export options (default: repository-permissions). Others JRS accepts include
  role-users, include-access-events, etc.

.EXAMPLE
  .\export_resource.ps1 -Uri /reports/geocoder/sales_dashboard -Out backups\sales_dashboard.zip
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Uri,
    [Parameter(Mandatory = $true)][string]$Out,
    [string[]]$Parameters = @("repository-permissions"),
    [int]$TimeoutSec = 120,
    [string]$ServerUrl,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")
$jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password
$auth = "$($jrs.User):$($jrs.Password)"
$base = "$($jrs.ServerUrl)/rest_v2/export"
if (-not $Uri.StartsWith("/")) { $Uri = "/$Uri" }

# --- request the export -------------------------------------------------------
$body = @{ uris = @($Uri); parameters = $Parameters } | ConvertTo-Json -Compress
$reqFile = [IO.Path]::GetTempFileName()
$body | Set-Content -Path $reqFile -Encoding utf8
try {
    $resp = & curl.exe -s -S -u $auth -X POST -H "Content-Type: application/json" `
        -H "Accept: application/json" --data-binary "@$reqFile" $base
} finally { Remove-Item $reqFile -ErrorAction SilentlyContinue }
$id = ($resp | ConvertFrom-Json).id
if (-not $id) { throw "export request failed: $resp" }
Write-Host "export id: $id"

# --- poll state ---------------------------------------------------------------
$deadline = (Get-Date).AddSeconds($TimeoutSec)
do {
    Start-Sleep -Milliseconds 800
    $state = & curl.exe -s -u $auth -H "Accept: application/json" "$base/$id/state"
    $phase = ($state | ConvertFrom-Json).phase
    if ($phase -eq "failed") { throw "export failed: $state" }
} while ($phase -ne "finished" -and (Get-Date) -lt $deadline)
if ($phase -ne "finished") { throw "export timed out after ${TimeoutSec}s (phase=$phase)" }

# --- download the archive -----------------------------------------------------
$outDir = Split-Path -Parent $Out
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Force $outDir | Out-Null }
$code = & curl.exe -s -o $Out -w "%{http_code}" -u $auth -H "Accept: application/zip" "$base/$id/exportFile"
if ("$code".Trim() -ne "200") { throw "download failed (HTTP $code)" }
$size = (Get-Item $Out).Length
Write-Host "OK: exported $Uri -> $Out ($size bytes)"
