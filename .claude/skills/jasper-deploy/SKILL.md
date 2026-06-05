---
name: jasper-deploy
description: >-
  Design, compile, and deploy JasperReports artifacts to JasperReports Server.
  Use when the user wants to scaffold a JasperReports report from a SQL query,
  generate or hand-edit a JR7 (JasperReports 7) .jrxml, compile a .jrxml to
  .jasper, publish/deploy a report to the Jasper(Reports) Server, or export/import
  (promote, back up, version-control) a dashboard or other repository resource.
  Covers the full design-compile-deploy pipeline against a local PostgreSQL
  database and a JasperReports Server REST v2 endpoint.
---

# JasperReports design / compile / deploy

Automates the pipeline for tabular JasperReports against PostgreSQL on this
machine, targeting JasperReports Server 10.0.0 over REST v2. Everything is
**JasperReports 7.0.6 native** — the jrxml schema is NOT 6.x compatible (see
`references/jr7-schema.md`).

## Toolchain (already on this machine)
- JR7 runtime jars: `C:\Users\rgorsuch\jasperreports-lib\` (incl. PostgreSQL
  driver and the `jasperreports-pdf` export module).
- JDK 11 (`C:\jdk-11.0.24+8`, also on PATH) — supports single-file source
  launch, so no separate `javac` step.
- `psql` 14 and `curl` 8.x on PATH.
- JasperReports Server (PRO/Enterprise) on **`http://localhost:8081/jasperserver-pro`**
  (REST v2, HTTP Basic auth). NOTE: a *different*, Bearer-token-gated Java
  service runs on :8080 — do not target it. The real install is `C:\Jaspersoft`.

## Workflow

### 1. Design — scaffold a JR7 jrxml from SQL
`scripts/scaffold_jrxml.py` introspects a query's result columns (via a psql
TEMP VIEW over `information_schema`), maps PostgreSQL types to Java field
classes, and emits a tabular JR7 report (title, column header, detail band,
page footer with "Page X of Y").

```powershell
# $skill points to the scripts/ subdirectory bundled with this skill.
# Use the base directory provided at the top of this skill's context:
$skill = "<skill-base-dir>\scripts"
# e.g. if invoked from the tx-geocoder project you can also use the repo-relative path:
# $skill = ".\.claude\skills\jasper-deploy\scripts"
$env:PGPASSWORD = "postgres"
python $skill\scaffold_jrxml.py `
    --name county_summary `
    --title "Texas County Edge Summary" `
    --subtitle "From the TIGER geocoder load" `
    --query "SELECT c.name AS county, count(*)::int AS edge_count FROM tiger_data.tx_edges l JOIN tiger.county c ON c.statefp='48' AND c.countyfp=l.countyfp GROUP BY 1 ORDER BY 2 DESC" `
    --out report\county_summary.jrxml
```
Use `--query-file q.sql` for long queries. Options: `--db --host --port --user`
(defaults: postgis_34_sample / localhost / 5432 / postgres), `--page-size
a4|letter`, `--landscape`. The scaffold is a starting point — refine layout by
hand using `references/jr7-schema.md`, or open it in Jaspersoft Studio.

Add a **JFreeChart chart** in the summary band with `--chart`:
```powershell
python $skill\scaffold_jrxml.py --name metro_pop --chart bar `
    --query "SELECT metro, sum(pop)::bigint AS population FROM ... GROUP BY metro" `
    --out report\metro_pop.jrxml
```
`--chart` = `pie|pie3d|bar|bar3d|line|area|stackedbar`. The category column
defaults to the first text column and the value to the first numeric column;
override with `--chart-category`, `--chart-value`, `--chart-series` (multi-series
category charts), `--chart-height`. Best with a small number of categories.

### 2. Compile — validate jrxml -> jasper
`scripts/compile_jrxml.ps1` compiles against the JR7 runtime. A clean compile is
the fastest check that the jrxml is JR7-valid before deploying.

```powershell
& $skill\compile_jrxml.ps1 -Jrxml report\county_summary.jrxml
```
(The SLF4J "No providers" lines are harmless.) To preview a PDF locally, fill
the `.jasper` against the DB with the existing `report\FillReport.java` helper.

### 2a. (one-time) Create the datasource a report will use
A report needs a JDBC datasource on the server to run. Create it once with
`scripts/create_datasource.ps1` (the PostgreSQL driver ships with JRS):

```powershell
& $skill\create_datasource.ps1 `
    -Uri /datasources/postgis_34_sample `
    -Label "PostGIS 34 Sample" `
    -Database postgis_34_sample -DbUser postgres -DbPassword postgres
```
Defaults target PostgreSQL `localhost:5432`; override with
`-DbHost -DbPort -DbUser -DbPassword`, or pass a full `-ConnectionUrl` and
`-DriverClass` for another engine. NOTE: PowerShell reserves `-Db` (alias of
`-Debug`), so the database-name parameter is `-Database`.

### 3. Deploy — publish to JasperReports Server (REST v2)
`scripts/deploy_report.ps1` wraps the jrxml in a reportUnit descriptor (jrxml
inlined as base64) and PUTs it to `/rest_v2/resources`, creating intermediate
folders. JRS compiles the jrxml server-side on first run.

```powershell
& $skill\deploy_report.ps1 `
    -Jrxml report\county_summary.jrxml `
    -TargetUri /reports/geocoder/county_summary `
    -Label "County Edge Summary" `
    -DataSourceUri /datasources/postgis_34_sample
```
Verified working: a live deploy to this server returns `201 Created` and the
report unit is retrievable at its URI.

**Credentials** resolve in order: script params → env vars
`JRS_URL`/`JRS_USER`/`JRS_PASS` → `jrs.config.json` in the skill root. Copy
`jrs.config.example.json` to `jrs.config.json` and fill it in; it is gitignored.
This server authenticates `superuser`/`superuser` over HTTP Basic on port 8081.

**The datasource referenced by `-DataSourceUri` must already exist** (create it
with step 2a). List existing datasources with (use **`type=jdbcDataSource`** —
the generic `type=dataSource` returns `204`/empty on this server and looks like
"no datasources"):
```powershell
curl.exe -s -u "${user}:${pass}" "http://localhost:8081/jasperserver-pro/rest_v2/resources?type=jdbcDataSource&recursive=true"
```

**Browse / delete deployed resources.** List everything under a folder (e.g. to
see what reports are deployed), and delete a resource (report unit, datasource,
etc.) by its repo URI:
```powershell
# list a folder's contents (drop &type= to see all resource kinds)
curl.exe -s -u "${user}:${pass}" "http://localhost:8081/jasperserver-pro/rest_v2/resources?folderUri=/reports/geocoder&recursive=true&type=reportUnit"
# delete one resource (204 No Content on success); the repo URI is appended after /rest_v2/resources
curl.exe -s -u "${user}:${pass}" -X DELETE "http://localhost:8081/jasperserver-pro/rest_v2/resources/reports/geocoder/county_summary"
```
Deleting a folder is recursive (removes the report units inside it). To redeploy
in bulk, loop `deploy_report.ps1 -Overwrite` over the `report\*.jrxml` files.

### 4. (optional) Run the report server-side to verify
```powershell
curl.exe -s -u "${user}:${pass}" -o out.pdf `
    "http://localhost:8081/jasperserver-pro/rest_v2/reports/reports/geocoder/county_summary.pdf"
```
A `200` and a `%PDF-` file confirm JRS compiled the jrxml, connected through the
datasource, filled, and exported. Re-deploying an existing report fails with
`409 versions not match` (optimistic locking) — pass **`-Overwrite`** to
`deploy_report.ps1` to delete-then-recreate.

**Other export formats** — the same synchronous endpoint just takes a different
extension. **Verified on this server** (all `200` with real content): `.xlsx`,
`.csv`, `.docx`, `.pptx` (also `.rtf`, `.ods`, `.odt`, `.xml`). e.g.
`.../rest_v2/reports/reports/geocoder/county_summary.xlsx`. The magic bytes
differ per format (`PK` for the Office/OpenDocument zip formats), so verify by
HTTP `200` + a non-trivial byte size rather than `%PDF-`.

**Big reports — async execution** (`rest_v2/reportExecutions`). The synchronous
`/reports/{uri}.{fmt}` endpoint blocks until the fill finishes and can time out
on large reports (the `tx_density_blockgroup_report*` reports are ~1 MB / tens of
thousands of rows). The async service queues the fill and lets you poll. **Verified
round-trip on this server.** NOTE: on Windows, pass the JSON body from a **file**
(`--data "@req.json"`) — an inline `-d '{...}'` gets its quotes mangled and the
server 400s with `serialization.error`.
```powershell
# 1. POST the request (body from a file to survive PowerShell/curl quoting)
'{"reportUnitUri":"/reports/geocoder/county_summary","outputFormat":"pdf","interactive":false,"async":true}' |
    Set-Content out\req.json -Encoding utf8
$rid = (curl.exe -s -u "${user}:${pass}" -H "Content-Type: application/json" -H "Accept: application/json" `
    --data "@out\req.json" "http://localhost:8081/jasperserver-pro/rest_v2/reportExecutions" | ConvertFrom-Json).requestId
# 2. poll until ready  ->  {"value":"ready"}
curl.exe -s -u "${user}:${pass}" -H "Accept: application/json" ".../rest_v2/reportExecutions/$rid/status"
# 3. download the output (exportId comes from GET .../reportExecutions/$rid -> exports[0].id)
curl.exe -s -o out.pdf -u "${user}:${pass}" ".../rest_v2/reportExecutions/$rid/exports/$exportId/outputResource"
```

**API source of truth for THIS server** — rather than the external community docs
(which version-drift and 403 scripted fetches), the live WADL lists every
`rest_v2` endpoint this exact 10.0.0 install exposes:
`http://localhost:8081/jasperserver-pro/rest_v2/application.wadl?detail=true`
(drop `?detail=true` for the core-only, shorter listing). See
`references/jrs-rest-api.md` for a distilled, verified-vs-doc-only endpoint map.

**Verify a whole folder of reports** — run each to PDF and check the HTTP code +
`%PDF-` magic + a non-trivial byte size. (Do NOT count `/Type /Page` objects as a
signal — the page tree is usually compressed, so the grep reads 0 on a perfectly
good PDF.) A `400` with an XML `errorDescriptor` body (magic `<?xml`) is a fill
failure — read it; a leading-`WITH` CTE in the query is a common cause (see
gotchas).
```bash
base="http://localhost:8081/jasperserver-pro/rest_v2/reports/reports/geocoder"
for r in county_summary metro_population_piechart tx_addr_zip_summary; do
  curl.exe -s -u "$user:$pass" -o "out/$r.pdf" -w "%{http_code}" "$base/$r.pdf"
  echo "  $r  $(head -c5 out/$r.pdf)  $(stat -c%s out/$r.pdf)b"
done
```
**Open a deployed folder in the JRS web UI:**
`http://localhost:8081/jasperserver-pro/flow.html?_flowId=searchFlow&folderUri=/reports/geocoder`

To **preview locally as an image** (handy for charts), fill + render a page to PNG:
```powershell
$env:PGPASSWORD = "postgres"
java --class-path "C:\Users\rgorsuch\jasperreports-lib\*" `
    report\RenderPng.java report\my_report.jasper out.png   # optional 3rd arg = page index
```

## Bulk deploy (e.g. the JR Library demo samples)
`scripts/deploy_jr_samples.ps1` walks a folder of `.jrxml`, deploys each under
`-TargetRoot`, and runs it to PDF to verify (writes a results CSV). A report
with no `<query>` is "standalone" (deploys + runs on an empty data source);
reports WITH a query are skipped unless you pass `-DataSourceUri`.
```powershell
# standalone samples (render with no data)
& $skill\deploy_jr_samples.ps1 -SamplesDir C:\Users\rgorsuch\jasperreports-7.0.6\demo\samples
# query-based samples (e.g. charts) against demo data
& $skill\deploy_jr_samples.ps1 -SamplesDir ...\demo\samples\charts -DataSourceUri /datasources/postgis_34_sample
```
The JR Library `charts` samples query an HSQLDB demo DB (`SELECT * FROM Orders`).
`report\translate_hsqldb_demo.py` translates `demo/hsqldb/test.script` →
PostgreSQL (handles `CREATE MEMORY TABLE` and `\uXXXX` escapes) so the tables
load into `postgis_34_sample` and the samples run against the existing data
source. Caveat: many library samples rely on parameters the Java harness
supplies (e.g. `MaxOrderID`) — without a default they render blank; pass them at
run time (`...PieChartReport.pdf?MaxOrderID=11077`) or bake in defaults.
`report\inject_chart_defaults.py` does the latter for the charts samples
(injects `<defaultValueExpression>` into self-closing `<parameter>` tags) so
they render with content from the JRS UI with no input. A `200`+valid-PDF only
means it ran, not that it has content — spot-check pages.

## File resources & CSV data adapters
`scripts/upload_file.ps1` uploads any local file to JRS as a repository file
resource (REST v2) — CSV/image/font/properties referenced by reports:
```powershell
& $skill\upload_file.ps1 -File data\foo.csv -Uri /reports/jr_samples/data/foo -Type csv
```
Verified: the file uploads and is retrievable at its repo URI, byte-intact.

**CSV-backed reports** reference a CSV via a `.jrdax` data adapter (a
`<csvDataAdapter>` with `fileName`=`repo:/path`, `useFirstRowAsHeader` or
explicit `columnNames`, `recordDelimiter` (CRLF=`&#13;&#10;`, preserved by JRS),
`fieldDelimiter`, `datePattern`, `queryExecuterMode`). Set the adapter on the
relevant `<dataset>`/subDataset with a `net.sf.jasperreports.data.adapter`
property (= the adapter's `repo:` URI) and remove any `dataSourceExpression`.
Upload the CSV and the `.jrdax` with `upload_file.ps1`; deploy companion
resources (resource bundles, images) embedded in the report unit with
`deploy_report.ps1 -ResourceFiles "name=path"`.
**Verified (subdataset adapters):** the `chartthemes` AllChartsReport (5 CSVs via
subdataset adapters) renders all chart themes this way.
**Verified (single-CSV main report, end-to-end):** `csv_metro_pop.jrxml` reads a
7-row CSV as its **main** dataset — no JDBC datasource, no `<query>` — via a
report-level `net.sf.jasperreports.data.adapter` property pointing at
`metro_pop_adapter.jrdax`; fields map to columns by header
(`useFirstRowAsHeader`), and a numeric column declared `class="java.lang.Integer"`
is summed in a variable (the adapter does the String→Integer conversion). Flow:
upload the CSV + `.jrdax` (`upload_file.ps1`), deploy the report **with no
datasource** (the "won't run until a datasource is attached" warning is expected
and wrong for adapter-backed reports), run to PDF → all rows render.
Gotchas that cause a silent 0-row or a fill error:
(1) **strip the UTF-8 BOM** from the CSV — it trips the parser with "Misplaced
quote"; match `recordDelimiter` to the CSV's real line endings (`&#10;` for LF,
`&#13;&#10;` for CRLF). (2) a report with `resourceBundle="X"` needs the
`.properties` bundle embedded (`-ResourceFiles "X.properties=..."`) even with
`whenResourceMissingType="Key"` (that only covers missing keys, not a missing
bundle). (3) **JR7 parses the `.jrdax` with strict Jackson** — an unknown element
throws `UnrecognizedPropertyException` at fill time (`400`), NOT a clean compile
error. JR6-era fields like `<useConnection>` are rejected; the only valid
`CsvDataAdapterImpl` elements are: `name, fileName, dataFile, fieldDelimiter,
recordDelimiter, useFirstRowAsHeader, columnNames, queryExecuterMode, datePattern,
numberPattern, encoding, timeZone, locale`.
The single-CSV *query-executer* report (`csvdatasource`, empty
`<query language="csv">`) is still a harder case — build that one in Jaspersoft
Studio — but the property-on-main-dataset form above needs no Studio.

## Dashboards (author in designer; promote via export/import)
**Do NOT try to compose a dashboard from scratch via `/rest_v2/resources`.** A JRS
dashboard (`resourceType=dashboard`) is a descriptor + three companion files
(`components` = frames, `layout` = a 40-wide grid of `<div data-componentId .../>`,
`wiring` = inter-frame events). You *can* PUT a hand-built model and the server
stores it (201) — but the JRS 10 client **silently won't render it**: the viewer
fetches the model and never executes the frames, and the **designer shows it
empty**, even when the stored model is byte-for-byte equivalent (same keys,
content-type `application/dashboardComponentsSchema+json`) to a working sample.
The designer does extra work on save that a raw resource PUT doesn't reproduce
and that isn't visible in the served model. This was investigated thoroughly and
abandoned — frames spin forever, no console error.

**Use the designer + export/import instead** (the supported path):
1. Author the dashboard once in the **designer**, dragging in already-deployed
   reports / ad hoc views, then Save:
   `http://localhost:8081/jasperserver-pro/dashboard/designer.html`
   (open an existing one at `dashboard/designer.html#<url-encoded uri>`).
2. **Version-control / back up / promote** it with the REST v2 export+import
   service (the archive is the designer's own output, so it re-imports and
   renders identically — ideal for dev→prod promotion across servers):
```powershell
& $skill\export_resource.ps1 -Uri /reports/geocoder/sales_dashboard -Out backups\sales_dashboard.zip
& $skill\import_resource.ps1 -Zip backups\sales_dashboard.zip      # -Update:$false to fail on existing
```
`export_resource.ps1`: POST `/rest_v2/export` `{uris,parameters}` → `{id}`, polls
`/rest_v2/export/{id}/state` until `phase=finished`, downloads
`/rest_v2/export/{id}/exportFile` (the download is **`/exportFile`** — a bare
`GET /rest_v2/export/{id}` returns `405`). `import_resource.ps1`: POSTs the zip
multipart to `/rest_v2/import?update=true`, polls `/rest_v2/import/{id}/state`.
Both export folders recursively (export a folder URI to grab a whole app).
**Verified:** round-trip export+import of the `1._Supermart_Dashboard` sample,
and a **destructive** round-trip of `5._Top_Performers` — export → DELETE the
dashboard (`resource.not.found`) → import → the full component model is restored
intact (all frames: charts, text dashlet, filter group, input control; plus the
embedded ad hoc views, `layout` and `wiring`). The export archive holds the
dashboard `.xml` descriptor + `_files/{components.data,layout,wiring.data}` +
each embedded ad hoc view. (Authoring remains the one manual, designer-only step
— only the export/import promotion/backup half is scriptable, and that is what's
verified here.)

**View a dashboard** in the HTML5 viewer (NOT a `flow.html` flow — there is no
`dashboardRuntimeFlow`; that errors "No flow definition found"). The resource URI
goes in the **URL-encoded hash fragment**:
`http://localhost:8081/jasperserver-pro/dashboard/viewer.html#%2Freports%2Fgeocoder%2Fsales_dashboard`

**Note on scope:** export/import promotes/versions dashboards; it does not *create*
them from data. Authoring is the one manual, UI step. (Ad Hoc views are likewise
web-UI-authored.) Everything else here — reports and their embedded charts — is
fully scripted.

## Notes / gotchas
- The live server is `jasperserver-pro` on **port 8081** (HTTP Basic). Port 8080
  hosts an unrelated Bearer-token-gated Java service that 401s every path — not JRS.
- **JRS SQL security validator**: report queries must begin with `SELECT`.
  A leading `WITH` (CTE) is rejected at fill time with a `JSSecurityException`
  (`Validator.validateSQL`) surfaced as a generic `400`/error UID. Window
  functions (`... over ()`) are fine. **This is a server-side check — a clean
  local `compile_jrxml.ps1` does NOT catch it** (the CTE is valid JR/SQL), so it
  only shows up on run-to-PDF. Always run a CTE-using report to PDF before
  declaring it deployed. **Fix:** push each CTE down into a nested subquery in
  the `FROM` clause so the statement starts with `SELECT`, e.g.
  `WITH a AS (...), b AS (... FROM a) SELECT ... FROM b`
  → `SELECT ... FROM (... FROM (...) a) b`. The `tx_density_blockgroup_report*`
  reference reports were converted this way (verify the rewrite in psql first —
  output must be identical).
- See **## Visualization components** below for charts, spider charts,
  barcodes/QR (community, local) and HTML5/FusionMaps (Pro, server-rendered).
- The full JRS 10.0.0 PDF docs are in `docs/` (machine-local, **gitignored** like
  the `jasperreports-lib` jars — authoritative offline source, the community site
  403s scripted fetches; read PDFs with `pypdfium2`, not the Read tool, since
  `pdftoppm` is unavailable). `references/jrs-rest-api.md` is the
  distilled, verified endpoint map with `docs/` page cites; it now also covers the
  `options` (saved input-control sets, verified), `queryExecutor` (Domain-only),
  `alerts`, and richer `reportExecutions` services, non-JDBC datasource types, and
  a **verified** Visualize.js cross-origin embedding recipe (serve the page
  outside the webapp; `domainWhitelist` controls CORS).
- In PowerShell, pass Maven/Java `-D...` args after `--%` if you script the
  underlying tools directly.
- Field `class` must match the JDBC column type or fill fails — the scaffolder
  handles this; if you hand-edit the SQL, keep `<field class>` in sync.
- Reference reports known to compile and render:
  `..\..\report\tx_density_blockgroup_report_jr7.jrxml` (tabular + groups),
  `..\..\report\metro_population_piechart.jrxml` (pie chart).

## Visualization components

Two tiers. **Community** components compile + preview locally (RenderPng) *and*
deploy. **Pro** components are authored in the legacy 6.x jrxml format and only
render server-side on JRS Pro — the open-source lib can't compile them, so
validate them by **deploy → run-to-PDF** (a `200` + a non-trivial PDF, and the
`.html` export containing the component markup, confirm a render).

**Verified (both tiers, end-to-end):** Community — `compile_jrxml.ps1` → `.jasper`
then `RenderPng` → PNG for JFreeChart pie/bar (`metro_population_piechart`,
`metro_population_bar`), spider/radar (`metro_population_spider`), and barcode4j
QR/DataMatrix/Code128 (`barcode_demo`) — all render offline from the local jars,
content matching the data. Pro — deploy → run-to-PDF → rasterize for HTML5
HighCharts (`metro_population_html5`) and FusionMaps choropleth
(`tx_county_density_map`, `tx_county_population_map`) — both render server-side
with correct data. (RenderPng note: the SLF4J "no providers" line goes to stderr;
under PowerShell `$ErrorActionPreference="Stop"` that can abort a wrapper script
even on a clean exit 0 — invoke the `java` compiler/renderer directly, or check
the `.jasper`/`.png` output rather than trusting the pipeline's error state.)

### Community (local + deploy)
Extra jars in `C:\Users\rgorsuch\jasperreports-lib` (outside this repo — rebuild
on a fresh clone, see below):
`jasperreports-charts-7.0.6.jar`, `jfreechart-1.5.6.jar`,
`jasperreports-barcode4j-7.0.6.jar`, `barcode4j-2.1.jar`, `zxing-core-3.4.0.jar`.

| Component | JR7 jrxml | Example |
|---|---|---|
| JFreeChart (pie/bar/line/area/…) | `<element kind="chart" chartType="…">` + `<dataset kind="pie\|category">` + `<plot>` | `metro_population_piechart.jrxml`, `metro_population_bar.jrxml` |
| Spider / radar | `<element kind="component"><component kind="spiderChart">` (chartSettings/dataset series-category-value/plot) | `metro_population_spider.jrxml` |
| Barcodes / QR | `<element kind="component"><component kind="barcode4j:QRCode\|DataMatrix\|Code128\|…">` + `<codeExpression>` | `barcode_demo.jrxml` |

Pie label tokens: `{0}`=key, `{1}`=value, `{2}`=percentage. A no-query report
(e.g. static barcodes) needs `whenNoDataType="AllSectionsNoDetail"` on the root
or it produces 0 pages. QR specifically needs `zxing-core` on the classpath.

**Rebuild the community jars** from the JR7 source (machine-local, not in repo):
```powershell
$env:JAVA_HOME = "C:\jdk-11.0.24+8"
& "C:\apache-maven-3.9.9\bin\mvn.cmd" -f "C:\Users\rgorsuch\jasperreports-7.0.6\pom.xml" `
    -pl ext/charts,ext/barcode4j -am --% -Dmaven.test.skip=true package
```
Copy the built `ext\charts\target\jasperreports-charts-7.0.6.jar` and
`ext\barcode4j\target\jasperreports-barcode4j-7.0.6.jar`, plus from `~\.m2`:
`org\jfree\jfreechart\1.5.6\jfreechart-1.5.6.jar`,
`net\sf\barcode4j\barcode4j\2.1\barcode4j-2.1.jar`,
`com\google\zxing\core\3.4.0\core-3.4.0.jar` (→ `zxing-core-3.4.0.jar`), into
`C:\Users\rgorsuch\jasperreports-lib`. (JFreeChart 1.5.x bundles jcommon.)

### Pro (server-rendered only; deploy → run to validate)
Authored in legacy 6.x jrxml (`xmlns="http://jasperreports.sourceforge.net/jasperreports"`,
`<componentElement>`, `<queryString>`, `<reportElement>`). The whole file must be
6.x — you can't mix JR7-native with these. JRS's `legacy-jrxml-*` modules convert
at fill time; **skip local compile**, deploy and run.

| Component | jrxml | Example |
|---|---|---|
| HTML5 charts (HighCharts) | `<hc:chart xmlns:hc="http://jaspersoft.com/highcharts" type="Column\|StackedBar\|…">` with `<hc:chartSetting>` + `<multiAxisData>` (`dataAxis` row buckets + `multiAxisMeasure`) | `metro_population_html5.jrxml` |
| FusionMaps choropleth | `<fm:map xmlns:fm="http://jaspersoft.com/fusion">` with `<fm:mapNameExpression>`, `<fm:colorRange>`s, `<fm:mapDataset><fm:entity>` (idExpression + valueExpression) | `tx_county_density_map.jrxml` |

**Gotcha:** a chart/map component bound to the main dataset and placed in a
band that fills *before* row iteration (e.g. `title`) must set
**`evaluationTime="Report"`**, or it binds zero data and renders blank/uniform
(no error). Put it in `summary`, or keep it in `title` with that attribute.

**Preview a Pro report as an image** (no local renderer for Pro components — use
the server's PDF and rasterize it): run to PDF, then
```bash
python -m pip install pypdfium2 Pillow   # one-time
python -c "import pypdfium2 as p; p.PdfDocument(r'out.pdf')[0].render(scale=3).to_pil().save(r'out.png')"
```

FusionMaps geometry lives in `…\jasperserver-pro\fusion\maps\fusioncharts.*.js`.
The installed **`Texas`** map (`fusioncharts.texas.js`) is keyed by **county FIPS**
(no zero-padding), so bind `idExpression` to `(countyfp::int)::text` — no lookup
table. Other Pro options present on this server: Fusion charts/gauges/widgets
(`jasperreports-fusion`), HighCharts heatmap/treemap/solid-gauge, and Ad Hoc
views/dashboards (web-UI, not jrxml). Get jrxml syntax from the bundled samples,
e.g. fetch `/public/Samples/Reports/ProfitDetailReport` (HTML5) or
`/public/Samples/Reports/14._World_Map` (FusionMaps) jrxml via REST.
