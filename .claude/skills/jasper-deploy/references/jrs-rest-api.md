# JasperReports Server 10.0.0 REST v2 — endpoint map (this install)

Distilled from the JRS 10.0.0 REST API Reference, scoped to the
report-design/deploy/run workflow this skill automates. Each entry is tagged:

- **[verified]** — exercised against this server (`localhost:8081/jasperserver-pro`,
  `superuser`/`superuser`, HTTP Basic) and confirmed working.
- **[doc-only]** — present in the docs / WADL but not yet exercised here; the
  payload/flow below is from the reference, treat as a starting point.

**Source of truth for this exact install:** the live WADL —
`http://localhost:8081/jasperserver-pro/rest_v2/application.wadl?detail=true`
(it never version-drifts the way the external community docs do, and the docs
site 403s scripted fetches anyway). Official reference:
<https://community.jaspersoft.com/documentation/jasperreports-server/tibco-jasperreports-server-rest-api-reference/v1000/jasperreports-server-rest-api-reference-_-overview/>

All paths below are under `…/jasperserver-pro/rest_v2/`. Auth is HTTP Basic on
every call. On **Windows**, POST/PUT JSON bodies from a **file**
(`--data "@req.json"`) — an inline `-d '{...}'` gets its quotes stripped by the
PowerShell→curl boundary and the server answers `400 serialization.error`.

---

## resources — repository CRUD  **[verified]**
The backbone the skill scripts already use.
- `GET  /resources?folderUri=/reports/geocoder&recursive=true&type=reportUnit`
  — list. Use `type=jdbcDataSource` for datasources (the generic `type=dataSource`
  returns `204`/empty on this server).
- `PUT  /resources{uri}?createFolders=true` (`Content-Type:
  application/repository.reportUnit+json`) — create/replace. See `deploy_report.ps1`.
- `DELETE /resources{uri}` — `204` on success; recursive on a folder.
- `GET  /resources{uri}` — fetch a resource descriptor (e.g. to read a deployed
  report's `jrxmlFileReference`, then `GET` that file URI to recover the jrxml —
  this is how the `uspopulation_tibcomaps` sample was pulled back out).

## reports — synchronous run  **[verified]**
- `GET /reports{uri}.{fmt}` — fill + export in one blocking call.
  Formats confirmed `200` here: **pdf, html, xlsx, csv, docx, pptx** (docs also
  list rtf, ods, odt, xml). Verify Office/OpenDocument output by `200` + size
  (magic is `PK`, not `%PDF-`).
- Pass report parameters / input-control values as query string:
  `…/PieChartReport.pdf?MaxOrderID=11077`.
- A `400` with an XML `errorDescriptor` body is a fill failure — read the
  `message`. Common causes here: a leading `WITH` CTE (server SQL validator —
  see SKILL.md gotchas), or an external resource the server can't reach (the
  TibcoMaps sample 400s on `maps.google.com`).

## reportExecutions — asynchronous run  **[verified]**
Proper path for large/slow fills that can time out on the synchronous endpoint.
1. `POST /reportExecutions` body `{"reportUnitUri":"…","outputFormat":"pdf",
   "interactive":false,"async":true}` → `{requestId, exports:[{id,status}]}`.
2. `GET /reportExecutions/{requestId}/status` → `{"value":"ready"}` when done
   (`queued`/`execution` while running).
3. `GET /reportExecutions/{requestId}/exports/{exportId}/outputResource` →
   the bytes. `exportId` is `exports[0].id` from step 1 (or re-`GET
   /reportExecutions/{requestId}`).
- Add more formats to one execution: `POST /reportExecutions/{requestId}/exports`.

## jobs — scheduling  **[doc-only]** (service present, `GET /jobs` → `204` empty)
Recurring / triggered / emailed report delivery.
- `GET  /jobs?reportUnitURI=/reports/geocoder/county_summary` — list jobs for a report.
- `PUT  /jobs` (`Content-Type: application/job+json`) — create a job: a
  `{trigger:{simpleTrigger|calendarTrigger}, source:{reportUnitURI, parameters},
  outputFormats, repositoryDestination | mailNotification}` descriptor.
- `POST /jobs/{id}` update · `DELETE /jobs/{id}` remove.

## permissions  **[doc-only]** (service present, `GET /permissions{uri}` → `204`)
- `GET /permissions{resourceUri}?effectivePermissions=true` — read ACLs.
- `PUT /permissions{uri}` — set a recipient→mask permission
  (`mask`: 0 none, 1 admin, 2 read+del, 6 read+write+del, 30 read, 32 execute).

## attributes  **[doc-only]**
Server/org/user key-value attributes — usable in datasource/report expressions
(`{attribute('name')}`), handy for not hard-coding DB creds per environment.
- `GET/PUT/DELETE /attributes` (server level),
  `…/organizations/{id}/attributes`, `…/users/{u}/attributes`.

## inputControls — parameterized reports  **[doc-only]**
- `GET /reports{uri}/inputControls` — the control definitions for a report.
- `GET /reports{uri}/inputControls/{id}/values` — selectable values (cascading
  controls supported). Drive an interactive report by passing chosen values as
  query params to the run endpoints above.

## import / export — promotion & backup  **[verified]**
Already wrapped by `export_resource.ps1` / `import_resource.ps1` (the supported
path for dashboards, and for moving any folder between servers).
- `POST /export {uris,parameters}` → `{id}`; poll `/export/{id}/state` until
  `phase=finished`; download `/export/{id}/exportFile` (the `/exportFile`
  suffix is required — a bare `GET /export/{id}` is `405`).
- `POST /import?update=true` (multipart zip); poll `/import/{id}/state`.

---

### Deliberately out of scope
Users/roles/organizations admin, domains/semantic layer, Ad Hoc / OLAP,
themes, diagnostics — present in the API but outside this skill's
geocoder-reporting remit. Discover them via the WADL if ever needed.
