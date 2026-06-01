<#
.SYNOPSIS
  Compile a JasperReports 7 .jrxml to .jasper, validating it against the JR7 engine.

.DESCRIPTION
  Uses JDK 11+ single-file source launch (no separate javac step) to run
  CompileReport.java against the JasperReports 7.0.6 runtime classpath.
  A clean compile is also the fastest validation that the jrxml is JR7-valid
  before deploying it to JasperReports Server.

.PARAMETER Jrxml
  Path to the .jrxml file to compile.

.PARAMETER LibDir
  Folder containing the JasperReports 7 jars. Defaults to the machine build.

.EXAMPLE
  .\compile_jrxml.ps1 -Jrxml ..\..\report\my_report.jrxml
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Jrxml,
    [string]$LibDir = "C:\Users\rgorsuch\jasperreports-lib"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Jrxml)) { throw "jrxml not found: $Jrxml" }
if (-not (Test-Path $LibDir)) { throw "JasperReports lib dir not found: $LibDir" }

$compiler = Join-Path $PSScriptRoot "CompileReport.java"
if (-not (Test-Path $compiler)) { throw "CompileReport.java missing next to this script" }

$jrxmlFull = (Resolve-Path $Jrxml).Path
$cp = Join-Path $LibDir "*"

Write-Host "Compiling $jrxmlFull ..."
& java --class-path $cp $compiler $jrxmlFull
$code = $LASTEXITCODE
if ($code -ne 0) { throw "compilation failed (exit $code)" }

$jasper = [System.IO.Path]::ChangeExtension($jrxmlFull, ".jasper")
if (-not (Test-Path $jasper)) { throw "compile reported success but $jasper is missing" }
Write-Host "OK: $jasper"
