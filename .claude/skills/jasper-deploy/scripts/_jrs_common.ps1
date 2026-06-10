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
  Invoke-JrsGet      - GET a resource (Accept json) -> { Code; Body }.
  Invoke-JrsRest     - generic call to ANY rest_v2 path (not just /resources):
                       arbitrary method, Content-Type, Accept, optional JSON body
                       from a file. Used by the jobs/alerts wrappers, whose
                       services live at /rest_v2/jobs and /rest_v2/alerts with
                       their own application/<type>+json media types and (for
                       alerts) inverted PUT-creates / POST-modifies verbs.
                       Returns { Code; Body }.
  Resolve-JrLib      - locate the JasperReports 7 runtime jar dir
                       (param -> env JR_LIB_DIR -> jrs.config jrLibDir -> default).
  Invoke-JrCompile   - compile a .jrxml to .jasper with CompileReport.java,
                       tolerating the harmless SLF4J-on-stderr that would
                       otherwise abort a $ErrorActionPreference=Stop caller;
                       returns $true iff the .jasper was produced.
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
        [Parameter(Mandatory)][string]$JsonFile,
        [switch]$Overwrite                       # update in place (no delete) and
                                                 # bypass the optimistic-lock 409
    )
    $url = "$($Jrs.ServerUrl)/rest_v2/resources$Uri" + "?createFolders=true"
    if ($Overwrite) { $url += "&overwrite=true" }
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

function Invoke-JrsGet {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Jrs, [Parameter(Mandatory)][string]$Uri,
          [string]$Accept = "application/json")
    $resp = & curl.exe -s -w "`n%{http_code}" -u "$($Jrs.User):$($Jrs.Password)" `
        -H "Accept: $Accept" "$($Jrs.ServerUrl)/rest_v2/resources$Uri"
    $lines = $resp -split "`n"
    $code = $lines[-1].Trim()
    $body = if ($lines.Length -ge 2) { ($lines[0..($lines.Length - 2)] -join "`n").Trim() } else { "" }
    return [pscustomobject]@{ Code = $code; Body = $body }
}

function Invoke-JrsRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Jrs,                  # object from Resolve-JrsConfig
        [Parameter(Mandatory)][string]$Method,       # GET | PUT | POST | DELETE
        [Parameter(Mandatory)][string]$Path,         # path under ServerUrl, e.g. /rest_v2/jobs (may include ?query)
        [string]$ContentType,                        # set for bodied requests
        [string]$Accept = "application/json",
        [string]$JsonFile                            # optional request-body file (survives PS->curl quoting)
    )
    # Build the full literal URL in one string before handing it to curl: an
    # inline "$base?query=..." expression at the PowerShell->curl boundary can
    # yield exit-code 000 (request never sent). Same root cause as the JSON-body
    # quoting gotcha -- keep complex args out of the inline boundary.
    $url = "$($Jrs.ServerUrl)$Path"
    $cArgs = @("-s", "-S", "-w", "`n%{http_code}", "-u", "$($Jrs.User):$($Jrs.Password)",
               "-X", $Method, "-H", "Accept: $Accept")
    if ($ContentType) { $cArgs += @("-H", "Content-Type: $ContentType") }
    if ($JsonFile)    { $cArgs += @("--data-binary", "@$JsonFile") }
    $cArgs += $url
    $resp = & curl.exe @cArgs
    $lines = $resp -split "`n"
    $code = $lines[-1].Trim()
    $body = if ($lines.Length -ge 2) { ($lines[0..($lines.Length - 2)] -join "`n").Trim() } else { "" }
    return [pscustomobject]@{ Code = $code; Body = $body }
}

function Resolve-JrLib {
    [CmdletBinding()]
    param([string]$LibDir)
    $cfgPath = Join-Path $PSScriptRoot "..\jrs.config.json"
    $cfg = if (Test-Path $cfgPath) { Get-Content $cfgPath -Raw | ConvertFrom-Json } else { $null }
    if ([string]::IsNullOrEmpty($LibDir)) { $LibDir = [Environment]::GetEnvironmentVariable("JR_LIB_DIR") }
    if ([string]::IsNullOrEmpty($LibDir) -and $cfg -and ($cfg.PSObject.Properties.Name -contains "jrLibDir")) { $LibDir = $cfg.jrLibDir }
    if ([string]::IsNullOrEmpty($LibDir)) { $LibDir = "C:\Users\rgorsuch\jasperreports-lib" }
    if (-not (Test-Path $LibDir)) {
        throw "JasperReports lib dir not found: $LibDir (set -LibDir, `$env:JR_LIB_DIR, or jrLibDir in jrs.config.json)"
    }
    return (Resolve-Path $LibDir).Path
}

function Invoke-JrCompile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Jrxml,
        [string]$LibDir,
        [switch]$PassThru          # also return compiler output text for diagnostics
    )
    $jrxmlFull = (Resolve-Path $Jrxml).Path
    $lib = Resolve-JrLib -LibDir $LibDir
    $cp = Join-Path $lib "*"
    $compiler = Join-Path $PSScriptRoot "CompileReport.java"
    if (-not (Test-Path $compiler)) { throw "CompileReport.java missing next to _jrs_common.ps1" }
    $jasper = [IO.Path]::ChangeExtension($jrxmlFull, ".jasper")
    if (Test-Path $jasper) { Remove-Item $jasper -Force }
    # The compiler prints a harmless "SLF4J: No providers" line to stderr; under
    # $ErrorActionPreference=Stop that becomes a terminating NativeCommandError
    # even on a clean exit. Run it under Continue and judge by the .jasper file.
    $out = & { $ErrorActionPreference = "Continue"; & java --class-path $cp $compiler $jrxmlFull 2>&1 }
    $ok = Test-Path $jasper
    if ($PassThru) { return [pscustomobject]@{ Ok = $ok; Jasper = $jasper; Output = ($out | Out-String) } }
    return $ok
}
