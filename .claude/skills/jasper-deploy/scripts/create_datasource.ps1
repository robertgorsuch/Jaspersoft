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
    [switch]$Overwrite,
    [string]$ServerUrl,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")

# --- resolve config (param -> env -> jrs.config.json, validated) ----------
$jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password
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
# --- optional overwrite: update the datasource IN PLACE -------------------
# A datasource referenced by reports can't be deleted (403), and a plain re-PUT
# hits JRS optimistic locking (409 "versions not match"). So fetch the current
# version and send it in the descriptor to update in place.
if ($Overwrite) {
    $cur = & curl.exe -s -w "`n%{http_code}" -u "$($jrs.User):$($jrs.Password)" `
        -H "Accept: application/json" "$($jrs.ServerUrl)/rest_v2/resources$Uri"
    $cl = $cur -split "`n"
    if ($cl[-1].Trim() -match '^2\d\d$') {
        try {
            $desc.version = (($cl[0..($cl.Length - 2)] -join "`n") | ConvertFrom-Json).version
            Write-Host "overwrite: updating existing $Uri (version $($desc.version))"
        } catch { }
    }
}

# --- PUT to REST v2 ------------------------------------------------------
$jsonFile = [IO.Path]::GetTempFileName()
($desc | ConvertTo-Json -Depth 4) | Set-Content -Path $jsonFile -Encoding utf8
Write-Host "(driver=$DriverClass)"
try {
    $r = Invoke-JrsPut -Jrs $jrs -Uri $Uri `
        -ContentType "application/repository.jdbcDataSource+json" -JsonFile $jsonFile
} finally {
    Remove-Item $jsonFile -ErrorAction SilentlyContinue
}

if ($r.Code -match '^2\d\d$') {
    Write-Host "OK ($($r.Code)): datasource $Uri"
    if ($r.Body) { Write-Host $r.Body }
} else {
    Write-Host "FAILED ($($r.Code))"
    if ($r.Body) { Write-Host $r.Body }
    throw "datasource create failed with HTTP $($r.Code)"
}
