<#
.SYNOPSIS
  Create (or list / get / delete) a JasperReports Server data-threshold alert via
  the REST v2 `alerts` service -- fire a notification when a watched report
  element's value crosses a threshold.

.DESCRIPTION
  Wraps the verified `/rest_v2/alerts` recipe. The alerts service INVERTS the
  usual REST verbs: PUT creates, POST modifies. BOTH Content-Type AND Accept must
  be `application/alert+json`. The descriptor is passed from a file so the
  PowerShell->curl boundary can't mangle the JSON.

  The alert watches one numeric report element identified by its design `uuid`
  (JR7 `<element uuid="...">`); JRS resolves it against the JasperPrint at fire
  time, so creation only validates the descriptor shape, not the element's
  existence. The alerts UI captures the uuid by click; via REST you supply it.

  Firing drives the evaluate->notify pipeline to the mail send; actual delivery
  needs a reachable SMTP host configured server-side
  (…/WEB-INF/js.quartz.properties; reloads only on a jasperreportsTomcat
  restart). See references/jrs-rest-api.md for the verified firing trace.

  Credentials resolve: params -> JRS_URL/JRS_USER/JRS_PASS -> jrs.config.json.

.PARAMETER Action
  create (default) | list | get | delete.

.PARAMETER ReportUri
  Repository URI of the report unit the alert runs, e.g.
  /reports/geocoder/county_summary. Required for create; optional filter for list.

.PARAMETER Id
  Numeric alert id (required for get/delete).

.PARAMETER Label
  Alert label (create). Defaults to "<report leaf> alert".

.PARAMETER ElementUuid
  Design uuid of the numeric report element to watch (required for create).

.PARAMETER DataPointName
  Name of the watched data point. Default "value".

.PARAMETER Operator
  Comparison. Accepts the JRS enums equals|notEqual|less|lessOrEqual|greater|
  greaterOrEqual, or the symbols == != < <= > >=. Required for create.

.PARAMETER Threshold
  Numeric threshold value (required for create).

.PARAMETER MailTo
  One or more recipient email addresses (required for create -- an alert with no
  toAddresses is rejected).

.PARAMETER DestinationFolder
  repositoryDestination folder (required by the service even for an email-only
  alert -- omitting it 400s error.report.alert.no.repository.output). Default:
  the report's parent folder.

.PARAMETER OutputFormats
  Output formats produced when the alert fires. Default: PDF.

.PARAMETER StartType
  now | at. Default: "at" when -StartDate is given, else "now".

.PARAMETER StartDate
  Fire time for StartType=at, "yyyy-MM-dd HH:mm:ss".

.PARAMETER Timezone
  Olson timezone. Default America/Chicago.

.PARAMETER OccurrenceCount
  Number of evaluations. 1 = once (default); -1 = forever (pair with
  -RecurrenceInterval/-RecurrenceIntervalUnit).

.PARAMETER RecurrenceInterval / -RecurrenceIntervalUnit
  Recurring evaluation cadence (MINUTE|HOUR|DAY|WEEK).

.EXAMPLE
  .\manage_alert.ps1 -ReportUri /reports/geocoder/county_summary `
      -Label "Edge count too high" -ElementUuid 5b1c... -Operator greater `
      -Threshold 500000 -MailTo ops@example.com

.EXAMPLE
  .\manage_alert.ps1 -Action list -ReportUri /reports/geocoder/county_summary
  .\manage_alert.ps1 -Action delete -Id 7
#>
[CmdletBinding()]
param(
    [ValidateSet("create", "list", "get", "delete")]
    [string]$Action = "create",
    [string]$ReportUri,
    [int]$Id,
    [string]$Label,
    [string]$ElementUuid,
    [string]$DataPointName = "value",
    [string]$Operator,
    [double]$Threshold,
    [string[]]$MailTo,
    [string]$DestinationFolder,
    [string[]]$OutputFormats = @("PDF"),
    [ValidateSet("now", "at")]
    [string]$StartType,
    [string]$StartDate,
    [string]$Timezone = "America/Chicago",
    [int]$OccurrenceCount = 1,
    [int]$RecurrenceInterval,
    [ValidateSet("MINUTE", "HOUR", "DAY", "WEEK")]
    [string]$RecurrenceIntervalUnit,
    [string]$ServerUrl,
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_jrs_common.ps1")
$jrs = Resolve-JrsConfig -ServerUrl $ServerUrl -User $User -Password $Password
$ALERT_MEDIA = "application/alert+json"

function leaf($uri) { $uri.Substring($uri.LastIndexOf("/") + 1) }
function parent($uri) { $uri.Substring(0, $uri.LastIndexOf("/")) }

# symbol -> JRS operator enum (the enums themselves pass through unchanged)
$OP_MAP = @{
    "==" = "equals"; "!=" = "notEqual"; "<>" = "notEqual"
    "<" = "less"; "<=" = "lessOrEqual"; ">" = "greater"; ">=" = "greaterOrEqual"
    "equals" = "equals"; "notEqual" = "notEqual"; "less" = "less"
    "lessOrEqual" = "lessOrEqual"; "greater" = "greater"; "greaterOrEqual" = "greaterOrEqual"
}

switch ($Action) {
    "list" {
        # the alert COLLECTION returns a summary representation, not the single
        # application/alert+json media type (that 406s) -- ask for plain JSON.
        $q = if ($ReportUri) { "?reportUnitURI=$ReportUri" } else { "" }
        $r = Invoke-JrsRest -Jrs $jrs -Method GET -Path "/rest_v2/alerts$q" -Accept "application/json"
        if ($r.Code -eq "204") { Write-Host "No alerts found."; return }
        if ($r.Code -notmatch '^2\d\d$') { throw "list failed ($($r.Code)): $($r.Body)" }
        Write-Output $r.Body          # to the output stream so callers can capture/pipe
        return
    }
    "get" {
        if (-not $Id) { throw "-Id is required for get" }
        $r = Invoke-JrsRest -Jrs $jrs -Method GET -Path "/rest_v2/alerts/$Id" -Accept $ALERT_MEDIA
        if ($r.Code -notmatch '^2\d\d$') { throw "get failed ($($r.Code)): $($r.Body)" }
        Write-Output $r.Body
        return
    }
    "delete" {
        if (-not $Id) { throw "-Id is required for delete" }
        $r = Invoke-JrsRest -Jrs $jrs -Method DELETE -Path "/rest_v2/alerts/$Id" -Accept $ALERT_MEDIA
        if ($r.Code -notmatch '^2\d\d$') { throw "delete failed ($($r.Code)): $($r.Body)" }
        Write-Host "OK ($($r.Code)): deleted alert $Id"
        return
    }
}

# --- create (PUT, per the inverted alerts verbs) --------------------------
if (-not $ReportUri) { throw "-ReportUri is required for create" }
if (-not $ReportUri.StartsWith("/")) { $ReportUri = "/$ReportUri" }
if (-not $ElementUuid) { throw "-ElementUuid is required for create (the watched element's design uuid)" }
if (-not $Operator) { throw "-Operator is required for create" }
if (-not $MailTo) { throw "-MailTo is required for create (an alert with no recipients is rejected)" }
if (-not $PSBoundParameters.ContainsKey("Threshold")) { throw "-Threshold is required for create" }
$op = $OP_MAP[$Operator]
if (-not $op) { throw "unknown -Operator '$Operator' (use equals|notEqual|less|lessOrEqual|greater|greaterOrEqual or == != < <= > >=)" }

if (-not $Label) { $Label = "$(leaf $ReportUri) alert" }
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
    if (-not $RecurrenceIntervalUnit) { throw "-RecurrenceInterval needs -RecurrenceIntervalUnit" }
    $simple.recurrenceInterval = $RecurrenceInterval
    $simple.recurrenceIntervalUnit = $RecurrenceIntervalUnit
}

$desc = [ordered]@{
    label                 = $Label
    trigger               = [ordered]@{ simpleTrigger = $simple }
    source                = [ordered]@{ reportUnitURI = $ReportUri }
    baseOutputFilename    = (leaf $ReportUri)
    outputFormats         = [ordered]@{ outputFormat = @($OutputFormats | ForEach-Object { $_.ToUpper() }) }
    repositoryDestination = [ordered]@{
        folderURI        = $DestinationFolder
        saveToRepository = $true
        overwriteFiles   = $true
    }
    mailNotification      = [ordered]@{
        # NOTE: unlike jobs, the alerts service wraps recipients in a
        # ClientAddressesListWrapper -- toAddresses is an object {address:[...]},
        # NOT a bare array (a bare array 400s serialization.error).
        toAddresses    = [ordered]@{ address = @($MailTo) }
        subject        = $Label
        messageText    = "Alert: $Label"
        resultSendType = "SEND_ATTACHMENT"
    }
    dataPointAlert        = [ordered]@{
        name          = $DataPointName
        dataPoint     = [ordered]@{ elementUUID = $ElementUuid }
        operator      = $op
        thresholdValue = "$Threshold"
        dataPointType = "NUMERIC"
        resourceURI   = $ReportUri
    }
}

$jsonFile = [IO.Path]::GetTempFileName()
($desc | ConvertTo-Json -Depth 8) | Set-Content -Path $jsonFile -Encoding utf8
try {
    $r = Invoke-JrsRest -Jrs $jrs -Method PUT -Path "/rest_v2/alerts" `
        -ContentType $ALERT_MEDIA -Accept $ALERT_MEDIA -JsonFile $jsonFile
} finally {
    Remove-Item $jsonFile -ErrorAction SilentlyContinue
}

if ($r.Code -match '^2\d\d$') {
    $newId = try { ($r.Body | ConvertFrom-Json).id } catch { $null }
    Write-Host "OK ($($r.Code)): created alert '$Label' on $ReportUri$(if ($newId) { " (id $newId)" })"
    if ($r.Body) { Write-Host $r.Body }
} else {
    Write-Host "FAILED ($($r.Code))"
    if ($r.Body) { Write-Host $r.Body }
    throw "alert create failed with HTTP $($r.Code): $($r.Body)"
}
