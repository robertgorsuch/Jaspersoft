<#
  Shared helpers for the jasper-deploy scripts. Dot-source it:
      . (Join-Path $PSScriptRoot "_jrs_common.ps1")

  Resolve-JrsConfig  - server URL + credentials, resolved param -> env
                       (JRS_URL/JRS_USER/JRS_PASS) -> jrs.config.json, with
                       validation and trailing-slash trim. Also returns the
                       config's dataSourceUri fallback.
  Invoke-JrsPut      - PUT a descriptor file to /rest_v2/resources and return
                       the HTTP code + body.
  Invoke-JrsDelete   - DELETE a resource and return the HTTP code.
#>

function Resolve-JrsConfig {
    [CmdletBinding()]
    param([string]$ServerUrl, [string]$User, [string]$Password)

    $cfgPath = Join-Path $PSScriptRoot "..\jrs.config.json"
    $cfg = if (Test-Path $cfgPath) { Get-Content $cfgPath -Raw | ConvertFrom-Json } else { $null }

    function pick($p, $e, $c) {
        if (-not [string]::IsNullOrEmpty($p)) { return $p }
        if ($e) { $v = [Environment]::GetEnvironmentVariable($e); if (-not [string]::IsNullOrEmpty($v)) { return $v } }
        if ($cfg -and ($cfg.PSObject.Properties.Name -contains $c)) { return $cfg.$c }
        return $null
    }

    $u   = pick $ServerUrl "JRS_URL"  "serverUrl"
    $usr = pick $User      "JRS_USER" "user"
    $pw  = pick $Password  "JRS_PASS" "password"

    if (-not $u) { throw "No server URL. Set -ServerUrl, `$env:JRS_URL, or serverUrl in jrs.config.json" }
    if (-not $usr -or -not $pw) { throw "No credentials. Set -User/-Password, `$env:JRS_USER/JRS_PASS, or user/password in jrs.config.json" }

    $ds = if ($cfg -and ($cfg.PSObject.Properties.Name -contains "dataSourceUri")) { $cfg.dataSourceUri } else { $null }
    return [pscustomobject]@{ ServerUrl = $u.TrimEnd("/"); User = $usr; Password = $pw; DataSourceUri = $ds }
}

function Invoke-JrsPut {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Jrs,          # object from Resolve-JrsConfig
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$ContentType,
        [Parameter(Mandatory)][string]$JsonFile
    )
    $url = "$($Jrs.ServerUrl)/rest_v2/resources$Uri" + "?createFolders=true"
    Write-Host "PUT $url"
    $resp = & curl.exe -s -S -w "`n%{http_code}" -u "$($Jrs.User):$($Jrs.Password)" `
        -X PUT -H "Content-Type: $ContentType" -H "Accept: application/json" `
        --data-binary "@$JsonFile" $url
    $lines = $resp -split "`n"
    $code = $lines[-1].Trim()
    $body = if ($lines.Length -ge 2) { ($lines[0..($lines.Length - 2)] -join "`n").Trim() } else { "" }
    return [pscustomobject]@{ Code = $code; Body = $body }
}

function Invoke-JrsDelete {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Jrs, [Parameter(Mandatory)][string]$Uri)
    $sink = [IO.Path]::GetTempFileName()
    try {
        $code = & curl.exe -s -o $sink -w "%{http_code}" -u "$($Jrs.User):$($Jrs.Password)" `
            -X DELETE "$($Jrs.ServerUrl)/rest_v2/resources$Uri"
    } finally { Remove-Item $sink -ErrorAction SilentlyContinue }
    return "$code".Trim()
}
