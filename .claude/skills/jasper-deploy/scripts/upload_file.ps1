<#
.SYNOPSIS
  Upload a local file to JasperReports Server as a repository file resource
  (REST v2). Useful for CSV/image/font/properties resources referenced by reports
  (e.g. a CSV data file a report reads via repo:/path).

.PARAMETER File     Local file to upload.
.PARAMETER Uri      Target repository URI, e.g. /reports/jr_samples/data/CsvDataSource
.PARAMETER Type     JRS file resource type: txt|csv|img|font|jrxml|prop|jar|xml|unspecified (default txt)
.PARAMETER Label    Optional label (defaults to last URI segment).

.EXAMPLE
  .\upload_file.ps1 -File data\CsvDataSource.txt -Uri /reports/jr_samples/data/CsvDataSource -Type csv
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$File,
    [Parameter(Mandatory)][string]$Uri,
    [string]$Type = "txt",
    [string]$Label,
    [switch]$Overwrite,
    [string]$ServerUrl, [string]$User, [string]$Password
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")
if (-not (Test-Path $File)) { throw "file not found: $File" }
$jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password
if (-not $Uri.StartsWith("/")) { $Uri = "/$Uri" }
if (-not $Label) { $Label = ($Uri -split "/")[-1] }

$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path $File)))
$desc = [ordered]@{ label = $Label; type = $Type; content = $b64 }
$json = [IO.Path]::GetTempFileName()
($desc | ConvertTo-Json) | Set-Content $json -Encoding utf8
try {
    if ($Overwrite) {
        $dc = Invoke-JrsDelete -Jrs $jrs -Uri $Uri
        Write-Host "overwrite: DELETE $Uri -> $dc"
        if ($dc -notmatch '^(2\d\d|404)$') { throw "overwrite: DELETE $Uri returned $dc; aborting before PUT" }
    }
    $r = Invoke-JrsPut -Jrs $jrs -Uri $Uri -ContentType "application/repository.file+json" -JsonFile $json
} finally { Remove-Item $json -ErrorAction SilentlyContinue }
if ($r.Code -match '^2\d\d$') { Write-Host "OK ($($r.Code)): file $Uri" }
else { Write-Host $r.Body; throw "upload failed HTTP $($r.Code)" }
