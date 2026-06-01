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
    [string]$ServerUrl, [string]$User, [string]$Password
)
$ErrorActionPreference = "Stop"
if (-not (Test-Path $File)) { throw "file not found: $File" }
$cfgPath = Join-Path $PSScriptRoot "..\jrs.config.json"
$cfg = if (Test-Path $cfgPath) { Get-Content $cfgPath -Raw | ConvertFrom-Json } else { $null }
function Resolve-Cfg($p,$e,$c){ if($p){return $p}; $v=[Environment]::GetEnvironmentVariable($e); if($v){return $v}; if($cfg -and ($cfg.PSObject.Properties.Name -contains $c)){return $cfg.$c}; return $null }
$ServerUrl = (Resolve-Cfg $ServerUrl "JRS_URL" "serverUrl").TrimEnd("/")
$User = Resolve-Cfg $User "JRS_USER" "user"; $Password = Resolve-Cfg $Password "JRS_PASS" "password"
if (-not $Uri.StartsWith("/")) { $Uri = "/$Uri" }
if (-not $Label) { $Label = ($Uri -split "/")[-1] }

$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path $File)))
$desc = [ordered]@{ label = $Label; type = $Type; content = $b64 }
$json = [IO.Path]::GetTempFileName()
($desc | ConvertTo-Json) | Set-Content $json -Encoding utf8
$url = "$ServerUrl/rest_v2/resources$Uri" + "?createFolders=true"
Write-Host "PUT $url (file type=$Type)"
try {
    $resp = & curl.exe -s -S -w "`n%{http_code}" -u "${User}:${Password}" -X PUT `
        -H "Content-Type: application/repository.file+json" -H "Accept: application/json" `
        --data-binary "@$json" $url
} finally { Remove-Item $json -ErrorAction SilentlyContinue }
$lines = $resp -split "`n"; $code = $lines[-1].Trim()
if ($code -match '^2\d\d$') { Write-Host "OK ($code): file $Uri" }
else { Write-Host ($lines[0..($lines.Length-2)] -join "`n"); throw "upload failed HTTP $code" }
