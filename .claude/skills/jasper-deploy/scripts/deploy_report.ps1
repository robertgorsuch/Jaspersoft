<#
.SYNOPSIS
  Deploy a .jrxml to JasperReports Server as a reportUnit via the REST v2 API.

.DESCRIPTION
  Builds a reportUnit descriptor with the jrxml inlined as base64 content and
  PUTs it to /rest_v2/resources (creating intermediate folders). The jrxml is
  uploaded as-is; JasperReports Server compiles it server-side on first run.
  A datasource reference is optional but a report won't run without one.

  Server URL and credentials are resolved in this order (first wins):
    1. -ServerUrl / -User / -Password parameters
    2. environment variables JRS_URL / JRS_USER / JRS_PASS
    3. jrs.config.json in the skill root (gitignored)

.PARAMETER Jrxml
  Path to the .jrxml to deploy.

.PARAMETER TargetUri
  Repository URI for the report unit, e.g. /reports/geocoder/county_summary
  (no spaces). The last segment becomes the resource id.

.PARAMETER Label
  Human-readable label. Defaults to the file base name.

.PARAMETER DataSourceUri
  Repository URI of an EXISTING datasource, e.g. /datasources/postgis_34_sample.

.EXAMPLE
  .\deploy_report.ps1 -Jrxml ..\..\report\county_summary.jrxml `
      -TargetUri /reports/geocoder/county_summary `
      -Label "County Edge Summary" `
      -DataSourceUri /datasources/postgis_34_sample
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Jrxml,
    [Parameter(Mandatory = $true)][string]$TargetUri,
    [string]$Label,
    [string]$Description = "",
    [string]$DataSourceUri,
    [switch]$Overwrite,
    [string]$ServerUrl,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Jrxml)) { throw "jrxml not found: $Jrxml" }
$jrxmlFull = (Resolve-Path $Jrxml).Path

# --- resolve config -------------------------------------------------------
$cfgPath = Join-Path $PSScriptRoot "..\jrs.config.json"
$cfg = $null
if (Test-Path $cfgPath) { $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json }

function Resolve-Setting($param, $envName, $cfgProp) {
    if (![string]::IsNullOrEmpty($param)) { return $param }
    $envVal = [Environment]::GetEnvironmentVariable($envName)
    if (![string]::IsNullOrEmpty($envVal)) { return $envVal }
    if ($cfg -and $cfg.PSObject.Properties.Name -contains $cfgProp) { return $cfg.$cfgProp }
    return $null
}

$ServerUrl = Resolve-Setting $ServerUrl "JRS_URL"  "serverUrl"
$User      = Resolve-Setting $User      "JRS_USER" "user"
$Password  = Resolve-Setting $Password  "JRS_PASS" "password"
if (-not $DataSourceUri) { $DataSourceUri = Resolve-Setting $null $null "dataSourceUri" }

if (-not $ServerUrl) { throw "No server URL. Set -ServerUrl, `$env:JRS_URL, or serverUrl in jrs.config.json" }
if (-not $User -or -not $Password) { throw "No credentials. Set -User/-Password, `$env:JRS_USER/JRS_PASS, or user/password in jrs.config.json" }
$ServerUrl = $ServerUrl.TrimEnd("/")
if (-not $TargetUri.StartsWith("/")) { $TargetUri = "/$TargetUri" }
if (-not $Label) { $Label = [System.IO.Path]::GetFileNameWithoutExtension($jrxmlFull) }

# --- build reportUnit descriptor -----------------------------------------
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($jrxmlFull))

$desc = [ordered]@{
    label       = $Label
    description = $Description
    jrxml       = [ordered]@{
        jrxmlFile = [ordered]@{
            label   = "$Label main jrxml"
            type    = "jrxml"
            content = $b64
        }
    }
}
if ($DataSourceUri) {
    $desc.dataSource = [ordered]@{ dataSourceReference = [ordered]@{ uri = $DataSourceUri } }
} else {
    Write-Warning "No datasource specified; report unit will be created but won't run until one is attached."
}

$jsonFile = [IO.Path]::GetTempFileName()
($desc | ConvertTo-Json -Depth 8) | Set-Content -Path $jsonFile -Encoding utf8

# --- optional overwrite: delete existing resource first ------------------
# JRS uses optimistic locking; re-PUTting over an existing report unit fails
# with 409 "versions not match". -Overwrite deletes it first (ignores 404).
if ($Overwrite) {
    $delUrl = "$ServerUrl/rest_v2/resources$TargetUri"
    $delCode = & curl.exe -s -o $null -w "%{http_code}" -u "${User}:${Password}" -X DELETE $delUrl
    Write-Host "overwrite: DELETE $TargetUri -> $delCode"
}

# --- PUT to REST v2 -------------------------------------------------------
$url = "$ServerUrl/rest_v2/resources$TargetUri" + "?createFolders=true"
Write-Host "PUT $url"
try {
    $resp = & curl.exe -s -S -w "`n%{http_code}" -u "${User}:${Password}" `
        -X PUT `
        -H "Content-Type: application/repository.reportUnit+json" `
        -H "Accept: application/json" `
        --data-binary "@$jsonFile" `
        $url
} finally {
    Remove-Item $jsonFile -ErrorAction SilentlyContinue
}

$lines = $resp -split "`n"
$httpCode = $lines[-1].Trim()
$body = ($lines[0..($lines.Length - 2)] -join "`n").Trim()

if ($httpCode -match '^2\d\d$') {
    Write-Host "OK ($httpCode): deployed $TargetUri"
    if ($body) { Write-Host $body }
} else {
    Write-Host "FAILED ($httpCode)"
    if ($body) { Write-Host $body }
    throw "deploy failed with HTTP $httpCode"
}
