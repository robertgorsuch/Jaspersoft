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
site 403s scripted fetches anyway).

**Authoritative offline docs (preferred over the community URL, which 403s
scripted fetches):** the full JRS 10.0.0 PDF set lives in `docs/` — machine-local
and **gitignored** (~62 MB, freely re-downloadable from Jaspersoft), like the
`jasperreports-lib` jars. The key one is
`docs/JasperReportsServerRESTAPIReferencev10.0.0.pdf` (344 pp) —
extract text with `pypdfium2` (`pdftoppm` isn't available, so the Read tool can't
rasterize it). Page map for the services below: resource descriptors p.44–63,
`resources` p.64, `permissions` p.99, `export` p.108 / `import` p.115,
`reports` p.131, `reportExecutions` p.137, `inputControls` p.161, `options`
p.188, `jobs` p.193, `alerts` p.235, `queryExecutor` p.294, `caches` p.298,
`organizations`/`users`/`roles` p.299–323, `attributes` p.325. Other relevant
guides in `docs/`: Visualize.js (embedding), Ultimate, User, Domains, Auth
Cookbook. Online mirror:
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
- **Datasource descriptor types** (ref p.46–51) — `create_datasource.ps1` only
  emits `jdbcDataSource`, but the resources service also takes
  `jndiJdbcDataSource`, `awsDataSource`, `virtualDataSource` (Teiid join over
  several DSs), `beanDataSource`, and `customDataSource`, each with its own
  `application/repository.<type>+json` content type and fields. Use these for a
  non-PostgreSQL/JDBC backend; the JDBC path is the one verified here.

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
- **More capabilities (doc-only, ref p.137–160):** export an already-run
  execution asynchronously, `POST /reportExecutions/{id}/parameters` to re-fill
  with changed input-control values, `…/{id}/exports/{exportId}/outputResource`
  + `…/attachments/…`, page status (`…/{id}/status?page=N`), bookmarks
  (`…/{id}/exports/{exportId}/bookmarks`), and raw parameter values.

## options — saved input-control value sets  **[verified]** (create→list→update→delete)
Report options are named sets of input-control values saved beside a report
(ref p.188); pair with the `inputControls` service. Verified on
`county_summary_param` (the `minEdges` control):
- `POST /reports{uri}/options?label=NAME` body `{"<controlId>":["<value>"], …}`
  (full literal URL — the inline `?label=` triggers the curl `000` quirk) →
  `200` `{uri,id,label}`; the option lands as a sibling resource
  (`/reports/geocoder/<NAME>`).
- `GET  /reports{uri}/options` → `{reportOptionsSummary:[{uri,id,label}]}`
  (`"No options found …"` when none).
- `PUT  /reports{uri}/options/{id}` body `{"<controlId>":[…]}` — update values.
- `DELETE /reports{uri}/options/{id}` — remove.

## queryExecutor — run a Domain query for raw data  **[verified, Domain-only]**
Returns query results without building a report — **but the only resource it
supports is a Domain** (ref p.294), so it's outside this skill's JDBC-report
scope (Domains are web-UI/semantic-layer authored). Verified the service
executes and returns the documented shape: `POST /queryExecutor{domainUri}`
(`Content-Type: application/xml`) with a `<query><queryFields><queryField
id="JoinTree.table.col"/>…</queryFields><queryFilterString>…</queryFilterString></query>`
→ `200` `{"names":[…],"values":[[…],…]}` (rows as bare value arrays). Field ids
come from the Domain schema via the **metadata** service:
`GET /domains{domainUri}/metadata` → `rootLevel.items[].properties.resourceId`.
A populated result needs a Domain whose backing datasource is live — the audit
domains were empty here and the sample foodmart Domain `400`s ("Review the Domain
settings", its DB isn't connected on this box).

## alerts — data-threshold notifications  **[doc-only]** (ref p.235)
The data-driven sibling of `jobs`: fire when a report value crosses a threshold.
`GET/POST/PUT/DELETE /alerts` (and `/alerts/{id}`, batch via `?id=…&id=…`,
`/alerts/pause|resume|restart`). Descriptor mirrors a job (`source`, trigger)
plus an `alertDataPoint` (the watched value + condition) and email output.

## jobs — scheduling  **[verified]** (full create→list→get→delete round-trip)
Recurring / triggered / emailed report delivery.
- `PUT /jobs` — create. **Both `Content-Type` AND `Accept` must be
  `application/job+json`** — a plain `application/json` Accept gives `406 Not
  Acceptable`. Returns the created job with a numeric `id`. Minimal descriptor
  that worked here (saves a PDF to the repo, once, at a future date):
  ```json
  {"label":"…","source":{"reportUnitURI":"/reports/geocoder/county_summary","parameters":{}},
   "trigger":{"simpleTrigger":{"timezone":"America/Chicago","startType":2,
     "startDate":"2026-12-01 09:00:00","occurrenceCount":1}},
   "baseOutputFilename":"county_summary_verify","outputFormats":{"outputFormat":["PDF"]},
   "repositoryDestination":{"folderURI":"/reports/geocoder","saveToRepository":true,"overwriteFiles":true}}
  ```
  `simpleTrigger.startType`: 1 = now, 2 = at `startDate` (`yyyy-MM-dd HH:mm:ss`);
  `occurrenceCount` 1 = once, -1 = forever (with `recurrenceInterval` +
  `recurrenceIntervalUnit`). Add `mailNotification` for email delivery.
- `GET  /jobs?reportUnitURI=/reports/geocoder/county_summary` — list (`204` if none).
- `GET  /jobs/{id}` — full descriptor (`Accept: application/job+json`).
- `DELETE /jobs/{id}` — `200`, echoes the id; afterward `GET /jobs/{id}` →
  `resource.not.found`.

## permissions  **[verified]** (set → confirm → restore round-trip)
A resource with no explicit ACL returns `204` and inherits from its parent
(geocoder inherits from `/`). Entries are `{uri, recipient:"role:/ROLE_X", mask}`.
- `GET /permissions{uri}` — explicit perms only (`204` = none/inherited).
- `GET /permissions{uri}?effectivePermissions=true` — resolved/inherited ACLs.
- `PUT /permissions{uri}` — **replace all explicit perms** on the resource.
  **`Content-Type: application/collection+json`** (NOT `…collection.permission+json`,
  which `415`s; that wrong guess cost two tries — the WADL is authoritative).
  Body: `{"permission":[{"uri":"repo:/reports/geocoder","recipient":"role:/ROLE_USER","mask":1}]}`.
- **Remove explicit perms / restore inheritance:** `PUT {"permission":[]}` → back to `204`.
- A single-permission `PUT`/`POST` (per WADL) uses plain `application/json`.
- `mask` values seen live: 1 = administer, 2 = read+delete (docs also: 6
  read+write+delete, 18 read+write, 30 read-only, 32 execute-only, 0 none).

> **Windows/PowerShell gotcha (both services):** an inline `"$baseUrl?query=…"`
> passed to `curl.exe` yields exit-code `000` (request never sent). Assign the
> **full literal URL to a variable first**, then pass the variable. Same root
> cause as the JSON-body quoting issue — keep complex args out of the inline
> PowerShell→curl boundary.

## attributes  **[verified]** (server-level scoped + user-level single, both round-tripped)
Server/org/user key-value attributes — usable in datasource/report expressions
(`{attribute('name')}`), handy for not hard-coding DB creds per environment.
Holders: server `/attributes` · org `/organizations/{id}/attributes` · user
`/users/{u}/attributes`. Entry shape: `{name, value, secure, inherited, holder}`.

- **User / org single attribute** — there's a per-name sub-resource
  `/users/{u}/attributes/{attrName}` (and `/organizations/{id}/…`):
  `PUT` a single `{"name":…,"value":…}` (`application/json`) → `201`;
  `GET` → `200`; `DELETE` → then `GET` is `resource.not.found`. Isolated and safe.
- **Server level has NO `/attributes/{name}` sub-resource** — only the collection
  at `/attributes`. ⚠️ **A bare `PUT /attributes` REPLACES ALL attributes** (this
  server has ~134 system attributes — mondrian/adhoc/log4j/etc.; a full PUT would
  wipe them). **Always scope the partial update with `?name=`:**
  `PUT /attributes?name=foo` body `{"attribute":[{"name":"foo","value":"bar"}]}`
  → updates only `foo`. **Verified:** count went 134 → 135 (delta exactly 1),
  the other 134 untouched. Multiple: repeat `&name=…`.
- `GET /attributes?name=foo` reads one; `DELETE /attributes?name=foo` removes one
  (also scoped — verified count restored 135 → 134).
- `secure:true` write-masks the value in reads; `?_embedded=...` and `hal+json`
  representations are available per the WADL.

## inputControls — parameterized reports  **[verified]** (author → discover → run)
Verified by deploying a parameterized geocoder report (`county_summary_param`:
`HAVING count(*) >= $P{minEdges}`) with an embedded control, then filtering it
via REST — `?minEdges=50000` shrank the output from 254 to 17 counties.

**Read / run flow:**
- `GET /reports{uri}/inputControls` — control definitions. Each has an `id`,
  a string `type` (e.g. `singleValueNumber`, `singleSelect`), and `state.options`.
- `GET /reports{uri}/inputControls/{id}/values` — selectable values (cascading
  controls supported; `200` even for a free single-value control).
- Run with the chosen value(s) as query params on the run endpoints:
  `…/reports{uri}.pdf?{controlId}=50000` (confirmed to filter; output size
  tracks the row count). The same works on `reportExecutions` via `parameters`.

**Authoring an input control in the report-unit descriptor** (what
`deploy_report.ps1` does *not* yet do — build the descriptor by hand). Several
non-obvious shapes, each found by reading the `400` body:
- `inputControls` on the report unit is a **flat array** (the `{inputControl:[…]}`
  XML nesting is wrong in JSON → `ArrayList … from Object value`).
- Each element is a **polymorphic wrapper object**: `{"inputControl":{…}}` for an
  inline control or `{"inputControlReference":{"uri":…}}` for a shared one
  (`known type ids = [inputControl, inputControlReference]`).
- The embedded control uses **legacy numeric type codes**, NOT the string enums
  the read API returns (`Cannot deserialize value of type 'byte' from String
  "singleValue"`): control `type` `2` = single value; the nested
  `dataType.dataType.type` is **ordinal** `0`=text, `1`=number, `2`=date,
  `3`=dateTime, `4`=time (so `1` for a numeric control — `2` silently yields a
  *date* control).
- **Binding:** the control's repo id = its URI last segment, derived from its
  **`label`** (spaces→`_`, case kept). That id MUST equal the jrxml `$P{param}`
  name or the value never reaches the query. (Set `label:"minEdges"`, put prose
  in `description`.) JRS materializes the inline control + dataType into
  `…_files/` sub-resources.
- Re-deploying `409`s (optimistic lock) — DELETE the report unit first
  (cascades the `_files`), confirm `404`, then PUT.
Minimal inline control that worked:
```json
"inputControls":[{"inputControl":{
  "label":"minEdges","description":"Minimum TIGER edge count per county",
  "mandatory":false,"readOnly":false,"visible":true,"type":2,
  "dataType":{"dataType":{"label":"minEdges number","type":1}}}}]
```

## import / export — promotion & backup  **[verified]**
Already wrapped by `export_resource.ps1` / `import_resource.ps1` (the supported
path for dashboards, and for moving any folder between servers). Verified two
ways: a Supermart dashboard round-trip, and a **destructive** geocoder round-trip
— export `county_summary` → DELETE it (`resource.not.found`) → import the zip →
report restored (original label / dataSourceReference / jrxmlFileReference) and
runs to a byte-identical PDF.
- `POST /export {uris,parameters}` → `{id}`; poll `/export/{id}/state` until
  `phase=finished`; download `/export/{id}/exportFile` (the `/exportFile`
  suffix is required — a bare `GET /export/{id}` is `405`). The zip is a `PK`
  archive: `index.xml` + `resources/<repo-path>.xml` descriptors + `*.data`
  blobs (jrxml etc.) + `.folder.xml` metadata + referenced datasources.
- `POST /import?update=true` (multipart `-F file=@…;type=application/zip`); poll
  `/import/{id}/state`. `update=false` fails on an existing resource.

---

### Embedding — Visualize.js  **[verified]**  (`docs/JasperReportsServerVisualize.jsGuide…pdf`)
Not a REST flow but the natural "what next" for deployed reports/dashboards: a
JS API to embed them in a web app. **Verified end-to-end** — `county_summary`
rendered into a `<div>` on a page served from a *different* origin (`:8000`),
authenticated cross-origin, success callback fired (driven headless via
Playwright + the installed Chrome; screenshot confirmed the interactive table).
Working page (served from any plain web server, NOT the JRS webapp):
```html
<script src="http://localhost:8081/jasperserver-pro/client/visualize.js"></script>
<div id="container"></div>
<script>
visualize({ server:"http://localhost:8081/jasperserver-pro",
            auth:{ name:"superuser", password:"superuser" } }, function(v){
  v.report({ resource:"/reports/geocoder/county_summary", container:"#container",
             success:function(){/*…*/}, error:function(e){/*…*/} });
});
</script>
```
Also `v.dashboard(…)`, `v.inputControls(…)`, `v.resourcesSearch(…)`. JRS ≥7.9
auto-generates this embed code from the repository UI.
**Gotchas found while verifying:**
- **Serve the embed page from OUTSIDE the JRS webapp.** Everything under
  `…/jasperserver-pro/` is behind the auth filter, so a page dropped in the webapp
  just 302-redirects to the login screen before your JS runs. Serve it from a
  separate origin (a plain `python -m http.server`) and let the `auth` block log
  in cross-origin.
- **`/client/visualize.js` loads anonymously (`200`, ~126 KB)** — but sending it
  HTTP **Basic** creds makes the form-auth filter `302` it; just request it with
  no `Authorization` header.
- **Cross-origin needs CORS**, controlled by the server `domainWhitelist`
  attribute (it's `*` here → `Access-Control-Allow-Origin: <your origin>` comes
  back; tighten it for production).
- **Headless capture:** Chrome `--screenshot --virtual-time-budget` fires before
  the async fill finishes (you get visualize's own "Loading…"). Use Playwright
  (`channel="chrome"`, no chromium download) and `wait_for_function` on a
  success flag, then screenshot.
Out of scope for *authoring*, but the deployed artifacts are directly embeddable.

### Deliberately out of scope
Users/roles/organizations admin, domains/semantic layer (incl. `queryExecutor`,
above), Ad Hoc / OLAP, themes, diagnostics, install/upgrade/security/telemetry —
present in the API and in the `docs/` PDFs, but outside this skill's
geocoder-reporting remit. Discover them via the WADL or the `docs/` guides if
ever needed.
