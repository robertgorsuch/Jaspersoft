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
    [string[]]$ResourceFiles,   # companion resources: "name=localpath" (bundles, images, subreports)
    [switch]$Overwrite,
    [string]$ServerUrl,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")

if (-not (Test-Path $Jrxml)) { throw "jrxml not found: $Jrxml" }
$jrxmlFull = (Resolve-Path $Jrxml).Path

# --- resolve config (param -> env -> jrs.config.json, validated) ----------
$jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password
if (-not $DataSourceUri) { $DataSourceUri = $jrs.DataSourceUri }
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

# optional companion resources embedded in the report unit (resource bundles,
# images, subreport .jasper, etc.). -ResourceFiles entries are "name=localpath".
if ($ResourceFiles) {
    $extType = @{ ".properties"="prop"; ".png"="img"; ".gif"="img"; ".jpg"="img"; ".jpeg"="img";
                  ".jrxml"="jrxml"; ".jasper"="jrxml"; ".ttf"="font"; ".xml"="xml" }
    $list = @()
    foreach ($rf in $ResourceFiles) {
        $name, $path = $rf -split "=", 2
        if (-not (Test-Path $path)) { throw "resource file not found: $path" }
        $ext = [IO.Path]::GetExtension($path).ToLower()
        $rtype = if ($extType.ContainsKey($ext)) { $extType[$ext] } else { "txt" }
        $rb64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path $path)))
        $list += [ordered]@{ name = $name; file = [ordered]@{ fileResource = [ordered]@{ label = $name; type = $rtype; content = $rb64 } } }
    }
    $desc.resources = [ordered]@{ resource = $list }
}

# --- optional overwrite: delete existing resource first ------------------
# JRS uses optimistic locking; re-PUTting over an existing report unit fails
# with 409 "versions not match". -Overwrite deletes it first. A delete that
# fails for any reason other than 404 (e.g. 403) is fatal, so we don't mask it
# as a misleading 409 on the PUT.
if ($Overwrite) {
    $delCode = Invoke-JrsDelete -Jrs $jrs -Uri $TargetUri
    Write-Host "overwrite: DELETE $TargetUri -> $delCode"
    if ($delCode -notmatch '^(2\d\d|404)$') {
        throw "overwrite: DELETE $TargetUri returned $delCode; aborting before PUT"
    }
}

# --- PUT to REST v2 -------------------------------------------------------
$jsonFile = [IO.Path]::GetTempFileName()
($desc | ConvertTo-Json -Depth 8) | Set-Content -Path $jsonFile -Encoding utf8
try {
    $r = Invoke-JrsPut -Jrs $jrs -Uri $TargetUri `
        -ContentType "application/repository.reportUnit+json" -JsonFile $jsonFile
} finally {
    Remove-Item $jsonFile -ErrorAction SilentlyContinue
}

if ($r.Code -match '^2\d\d$') {
    Write-Host "OK ($($r.Code)): deployed $TargetUri"
    if ($r.Body) { Write-Host $r.Body }
} else {
    Write-Host "FAILED ($($r.Code))"
    if ($r.Body) { Write-Host $r.Body }
    throw "deploy failed with HTTP $($r.Code)"
}
