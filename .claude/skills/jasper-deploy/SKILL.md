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
datasource, filled, and exported.

## Notes / gotchas
- The live server is `jasperserver-pro` on **port 8081** (HTTP Basic). Port 8080
  hosts an unrelated Bearer-token-gated Java service that 401s every path — not JRS.
- In PowerShell, pass Maven/Java `-D...` args after `--%` if you script the
  underlying tools directly.
- Field `class` must match the JDBC column type or fill fails — the scaffolder
  handles this; if you hand-edit the SQL, keep `<field class>` in sync.
- Reference report that is known to compile and render:
  `..\..\report\tx_density_blockgroup_report_jr7.jrxml`.
