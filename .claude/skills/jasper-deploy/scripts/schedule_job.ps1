<#
.SYNOPSIS
  Schedule (or list / get / delete) a JasperReports Server report job via the
  REST v2 `jobs` service -- recurring, triggered, or one-off report delivery to
  the repository and/or by email.

.DESCRIPTION
  Wraps the verified `/rest_v2/jobs` recipe. Creating a job PUTs a job
  descriptor; BOTH Content-Type AND Accept must be `application/job+json` (a
  plain application/json Accept gives 406 Not Acceptable). The descriptor is
  passed from a file so PowerShell->curl quoting can't mangle it.

  Server URL and credentials resolve in this order (first wins):
    1. -ServerUrl / -User / -Password parameters
    2. environment variables JRS_URL / JRS_USER / JRS_PASS
    3. jrs.config.json in the skill root (gitignored)

.PARAMETER Action
  create (default) | list | get | delete.

.PARAMETER ReportUri
  Repository URI of the report unit to schedule, e.g.
  /reports/geocoder/county_summary. Required for create; optional filter for list.

.PARAMETER Id
  Numeric job id (required for get/delete).

.PARAMETER Label
  Job label (create). Defaults to "<report leaf> scheduled".

.PARAMETER StartType
  now | at. Default: "at" when -StartDate is given, else "now".

.PARAMETER StartDate
  Fire time for StartType=at, "yyyy-MM-dd HH:mm:ss" (local to -Timezone).

.PARAMETER Timezone
  Olson timezone for the trigger. Default America/Chicago.

.PARAMETER OccurrenceCount
  Number of fires. 1 = once (default). For a recurring job set this to -1 (or any
  count > 1) AND pass -RecurrenceInterval/-RecurrenceIntervalUnit.

.PARAMETER RecurrenceInterval
  Interval count for a recurring simpleTrigger (e.g. 1).

.PARAMETER RecurrenceIntervalUnit
  MINUTE | HOUR | DAY | WEEK. Pair with -RecurrenceInterval.

.PARAMETER OutputFormats
  One or more of PDF, HTML, XLSX, CSV, DOCX, PPTX, RTF, ODS, ODT, XML.
  Default: PDF.

.PARAMETER BaseOutputFilename
  Output file base name (no extension). Default: the report leaf name.

.PARAMETER DestinationFolder
  Repository folder the output is written to. Default: the report's parent folder.

.PARAMETER MailTo
  One or more email addresses; adds a mailNotification (SEND_ATTACHMENT).

.PARAMETER Parameters
  Hashtable of report parameter/input-control values to bake into the job.

.EXAMPLE
  # one-off PDF saved to the repo at a future date
  .\schedule_job.ps1 -ReportUri /reports/geocoder/county_summary `
      -Label "County summary monthly" -StartDate "2026-12-01 09:00:00"

.EXAMPLE
  # every day forever, emailed
  .\schedule_job.ps1 -ReportUri /reports/geocoder/county_summary `
      -StartType now -OccurrenceCount -1 -RecurrenceInterval 1 -RecurrenceIntervalUnit DAY `
      -OutputFormats PDF,XLSX -MailTo ops@example.com

.EXAMPLE
  .\schedule_job.ps1 -Action list -ReportUri /reports/geocoder/county_summary
  .\schedule_job.ps1 -Action delete -Id 42
#>
[CmdletBinding()]
param(
    [ValidateSet("create", "list", "get", "delete")]
    [string]$Action = "create",
    [string]$ReportUri,
    [int]$Id,
    [string]$Label,
    [ValidateSet("now", "at")]
    [string]$StartType,
    [string]$StartDate,
    [string]$Timezone = "America/Chicago",
    [int]$OccurrenceCount = 1,
    [int]$RecurrenceInterval,
    [ValidateSet("MINUTE", "HOUR", "DAY", "WEEK")]
    [string]$RecurrenceIntervalUnit,
    [string[]]$OutputFormats = @("PDF"),
    [string]$BaseOutputFilename,
    [string]$DestinationFolder,
    [string[]]$MailTo,
    [hashtable]$Parameters,
    [string]$ServerUrl,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")
$jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password
$JOB_MEDIA = "application/job+json"

function leaf($uri) { $uri.Substring($uri.LastIndexOf("/") + 1) }
function parent($uri) { $uri.Substring(0, $uri.LastIndexOf("/")) }

switch ($Action) {
    "list" {
        $q = if ($ReportUri) { "?reportUnitURI=$ReportUri" } else { "" }
        $r = Invoke-JrsRest -Jrs $jrs -Method GET -Path "/rest_v2/jobs$q"
        if ($r.Code -eq "204") { Write-Host "No jobs found."; return }
        if ($r.Code -notmatch '^2\d\d$') { throw "list failed ($($r.Code)): $($r.Body)" }
        Write-Output $r.Body          # to the output stream so callers can capture/pipe
        return
    }
    "get" {
        if (-not $Id) { throw "-Id is required for get" }
        $r = Invoke-JrsRest -Jrs $jrs -Method GET -Path "/rest_v2/jobs/$Id" -Accept $JOB_MEDIA
        if ($r.Code -notmatch '^2\d\d$') { throw "get failed ($($r.Code)): $($r.Body)" }
        Write-Output $r.Body
        return
    }
    "delete" {
        if (-not $Id) { throw "-Id is required for delete" }
        $r = Invoke-JrsRest -Jrs $jrs -Method DELETE -Path "/rest_v2/jobs/$Id"
        if ($r.Code -notmatch '^2\d\d$') { throw "delete failed ($($r.Code)): $($r.Body)" }
        Write-Host "OK ($($r.Code)): deleted job $Id"
        return
    }
}

# --- create ---------------------------------------------------------------
if (-not $ReportUri) { throw "-ReportUri is required for create" }
if (-not $ReportUri.StartsWith("/")) { $ReportUri = "/$ReportUri" }
if (-not $Label) { $Label = "$(leaf $ReportUri) scheduled" }
if (-not $BaseOutputFilename) { $BaseOutputFilename = leaf $ReportUri }
if (-not $DestinationFolder) { $DestinationFolder = parent $ReportUri }
if (-not $StartType) { $StartType = if ($StartDate) { "at" } else { "now" } }
if ($StartType -eq "at" -and -not $StartDate) { throw "-StartDate is required when -StartType is 'at'" }

$simple = [ordered]@{
    timezone        = $Timezone
    startType       = if ($StartType -eq "now") { 1 } else { 2 }
    occurrenceCount = $OccurrenceCount
}
if ($StartType -eq "at") { $simple.startDate = $StartDate }
if ($RecurrenceInterval) {
    if (-not $RecurrenceIntervalUnit) { throw "-RecurrenceInterval needs -RecurrenceIntervalUnit (MINUTE|HOUR|DAY|WEEK)" }
    $simple.recurrenceInterval = $RecurrenceInterval
    $simple.recurrenceIntervalUnit = $RecurrenceIntervalUnit
}

$desc = [ordered]@{
    label   = $Label
    source  = [ordered]@{
        reportUnitURI = $ReportUri
        parameters    = if ($Parameters) { $Parameters } else { @{} }
    }
    trigger = [ordered]@{ simpleTrigger = $simple }
    baseOutputFilename    = $BaseOutputFilename
    outputFormats         = [ordered]@{ outputFormat = @($OutputFormats | ForEach-Object { $_.ToUpper() }) }
    repositoryDestination = [ordered]@{
        folderURI        = $DestinationFolder
        saveToRepository = $true
        overwriteFiles   = $true
    }
}
if ($MailTo) {
    $desc.mailNotification = [ordered]@{
        toAddresses    = @($MailTo)
        subject        = $Label
        messageText    = "Scheduled report: $Label"
        resultSendType = "SEND_ATTACHMENT"
    }
}

$jsonFile = [IO.Path]::GetTempFileName()
($desc | ConvertTo-Json -Depth 8) | Set-Content -Path $jsonFile -Encoding utf8
try {
    $r = Invoke-JrsRest -Jrs $jrs -Method PUT -Path "/rest_v2/jobs" `
        -ContentType $JOB_MEDIA -Accept $JOB_MEDIA -JsonFile $jsonFile
} finally {
    Remove-Item $jsonFile -ErrorAction SilentlyContinue
}

if ($r.Code -match '^2\d\d$') {
    $newId = try { ($r.Body | ConvertFrom-Json).id } catch { $null }
    Write-Host "OK ($($r.Code)): scheduled job '$Label' on $ReportUri$(if ($newId) { " (id $newId)" })"
    if ($r.Body) { Write-Host $r.Body }
} else {
    Write-Host "FAILED ($($r.Code))"
    if ($r.Body) { Write-Host $r.Body }
    throw "schedule failed with HTTP $($r.Code): $($r.Body)"
}
