<#
.SYNOPSIS
  Create (or update) a JDBC datasource on JasperReports Server via REST v2.

.DESCRIPTION
  PUTs an application/repository.jdbcDataSource+json descriptor to
  /rest_v2/resources, creating intermediate folders. The target DB's JDBC
  driver must be on the JRS server classpath (the PostgreSQL driver ships with
  JasperReports Server). Reports deployed by deploy_report.ps1 reference a
  datasource by its repository URI (-DataSourceUri).

  Server URL and credentials resolve the same way as deploy_report.ps1:
    1. -ServerUrl / -User / -Password parameters
    2. environment variables JRS_URL / JRS_USER / JRS_PASS
    3. jrs.config.json in the skill root (gitignored)

.PARAMETER Uri
  Repository URI for the datasource, e.g. /datasources/postgis_34_sample.

.PARAMETER Label
  Human-readable label. Defaults to the last URI segment.

.PARAMETER ConnectionUrl
  Full JDBC URL. If omitted, built from -DbHost/-DbPort/-Db as a PostgreSQL URL.

.EXAMPLE
  .\create_datasource.ps1 -Uri /datasources/postgis_34_sample `
      -Label "PostGIS 34 Sample" -Database postgis_34_sample `
      -DbUser postgres -DbPassword postgres
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Uri,
    [string]$Label,
    [string]$Description = "",
    [string]$ConnectionUrl,
    [string]$DriverClass = "org.postgresql.Driver",
    [string]$DbHost = "localhost",
    [int]$DbPort = 5432,
    [string]$Database = "postgis_34_sample",
    [string]$DbUser = "postgres",
    [string]$DbPassword = "postgres",
    [string]$ServerUrl,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"

# --- resolve config (shared convention with deploy_report.ps1) -----------
$cfgPath = Join-Path $PSScriptRoot "..\jrs.config.json"
$cfg = $null
if (Test-Path $cfgPath) { $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json }

function Resolve-Setting($param, $envName, $cfgProp) {
    if (![string]::IsNullOrEmpty($param)) { return $param }
    if ($envName) {
        $envVal = [Environment]::GetEnvironmentVariable($envName)
        if (![string]::IsNullOrEmpty($envVal)) { return $envVal }
    }
    if ($cfg -and $cfg.PSObject.Properties.Name -contains $cfgProp) { return $cfg.$cfgProp }
    return $null
}

$ServerUrl = Resolve-Setting $ServerUrl "JRS_URL"  "serverUrl"
$User      = Resolve-Setting $User      "JRS_USER" "user"
$Password  = Resolve-Setting $Password  "JRS_PASS" "password"

if (-not $ServerUrl) { throw "No server URL. Set -ServerUrl, `$env:JRS_URL, or serverUrl in jrs.config.json" }
if (-not $User -or -not $Password) { throw "No credentials. Set -User/-Password, env vars, or jrs.config.json" }
$ServerUrl = $ServerUrl.TrimEnd("/")
if (-not $Uri.StartsWith("/")) { $Uri = "/$Uri" }
if (-not $Label) { $Label = ($Uri -split "/")[-1] }
if (-not $ConnectionUrl) { $ConnectionUrl = "jdbc:postgresql://${DbHost}:${DbPort}/${Database}" }

# --- build jdbcDataSource descriptor -------------------------------------
$desc = [ordered]@{
    label         = $Label
    description   = $Description
    driverClass   = $DriverClass
    connectionUrl = $ConnectionUrl
    username      = $DbUser
    password      = $DbPassword
}
$jsonFile = [IO.Path]::GetTempFileName()
($desc | ConvertTo-Json -Depth 4) | Set-Content -Path $jsonFile -Encoding utf8

# --- PUT to REST v2 ------------------------------------------------------
$url = "$ServerUrl/rest_v2/resources$Uri" + "?createFolders=true"
Write-Host "PUT $url  (driver=$DriverClass)"
try {
    $resp = & curl.exe -s -S -w "`n%{http_code}" -u "${User}:${Password}" `
        -X PUT `
        -H "Content-Type: application/repository.jdbcDataSource+json" `
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
    Write-Host "OK ($httpCode): datasource $Uri"
    if ($body) { Write-Host $body }
} else {
    Write-Host "FAILED ($httpCode)"
    if ($body) { Write-Host $body }
    throw "datasource create failed with HTTP $httpCode"
}
