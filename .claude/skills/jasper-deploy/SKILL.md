---
name: jasper-deploy
description: >-
  Design, compile, and deploy JasperReports artifacts to JasperReports Server.
  Use when the user wants to scaffold a JasperReports report from a SQL query,
  generate or hand-edit a JR7 (JasperReports 7) .jrxml, compile a .jrxml to
  .jasper, or publish/deploy a report to the Jasper(Reports) Server. Covers the
  full design -> compile -> deploy pipeline against a local PostgreSQL database
  and a JasperReports Server REST v2 endpoint.
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
Examples below assume you run from the repo root (`C:\Users\rgorsuch\tx-geocoder`).
`$skill` is just shorthand for the scripts dir; paths the scripts read/write are
otherwise unrestricted (absolute paths work fine).
```powershell
$skill = ".\.claude\skills\jasper-deploy\scripts"
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
with step 2a). List existing datasources with:
```powershell
curl.exe -s -u "${user}:${pass}" "http://localhost:8081/jasperserver-pro/rest_v2/resources?type=dataSource&recursive=true"
```

### 4. (optional) Run the report server-side to verify
```powershell
curl.exe -s -u "${user}:${pass}" -o out.pdf `
    "http://localhost:8081/jasperserver-pro/rest_v2/reports/reports/geocoder/county_summary.pdf"
```
A `200` and a `%PDF-` file confirm JRS compiled the jrxml, connected through the
datasource, filled, and exported. Re-deploying an existing report fails with
`409 versions not match` (optimistic locking) — pass **`-Overwrite`** to
`deploy_report.ps1` to delete-then-recreate.

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
`<csvDataAdapter>` with `fileName`, `columnNames`, `recordDelimiter`,
`queryExecuterMode`) pointed at the uploaded file (`fileName` =
`repo:/path` or relative), and the report carries a
`net.sf.jasperreports.data.adapter` property naming the adapter.
**Status/caveat:** wiring the JR Library CSV samples (e.g. `csvdatasource`,
`chartthemes`) this way over REST proved unreliable — the adapter chain resolves
(per server stack traces) but reports can render 0 rows with no error, due to
query-executer-vs-datasource-mode and delimiter subtleties. The dependable path
is to build + test-preview the CSV data adapter in **Jaspersoft Studio** and
publish it to JRS, then deploy the report referencing it.

## Notes / gotchas
- The live server is `jasperserver-pro` on **port 8081** (HTTP Basic). Port 8080
  hosts an unrelated Bearer-token-gated Java service that 401s every path — not JRS.
- **JRS SQL security validator**: report queries must begin with `SELECT`.
  A leading `WITH` (CTE) is rejected at fill time with a `JSSecurityException`
  (`Validator.validateSQL`) surfaced as a generic `400`/error UID — rewrite CTEs
  as nested subqueries. Window functions (`... over ()`) are fine.
- See **## Visualization components** below for charts, spider charts,
  barcodes/QR (community, local) and HTML5/FusionMaps (Pro, server-rendered).
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
