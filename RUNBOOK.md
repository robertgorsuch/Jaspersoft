# Texas PostGIS Geocoder + Population Maps + JasperReports — Runbook

Cumulative knowledge from building a **statewide Texas address geocoder** on PostGIS, a set of
**population density visualizations**, and a **JasperReports 7** report over the same data.

> Conventions: `psql`/PostgreSQL **14** at `C:\Program Files\PostgreSQL\14\bin`. Database
> **`postgis_34_sample`** on `localhost:5432`, user/pw **`postgres` / `<your local password>` (set via $env:PGPASSWORD)**. Staging dir **`C:\gisdata`**.

---

## 1. What exists

- **Statewide TIGER geocoder** in `postgis_34_sample` — all **254 Texas counties** loaded
  (edges 5,692,076 · featnames 5,060,971 · addr 2,664,841 · faces 1,924,566 · place 1,860),
  plus nation state/county. `geocode('1100 Congress Ave, Austin, TX 78701')` → rating 0.
- **Population data**: `tiger_data.tx_tabblock20` (668,757 2020 census blocks, statewide, with `pop`),
  `tiger_data.tx_bg` (18,638 block groups), `tiger_data.tx_tract` (6,896 tracts). TX total pop 29,145,505.
- **Maps** (in `maps\`, open in a browser): statewide heatmap (2 km grid), Houston heatmap (500 m),
  full block-detail heatmap (449k blocks), tract choropleth, block-group choropleth, and two geocode-pin maps.
- **JasperReports** (in `report\`): a block-group density report in both 6.x and native JR 7 form,
  compiled (`.jasper`) and rendered (`output\tx_density_blockgroup_report.pdf`, 317 pages).

## 2. Prerequisites / environment (this machine)

| Tool | Location | Notes |
|------|----------|-------|
| PostgreSQL + PostGIS 3.4 | `C:\Program Files\PostgreSQL\14\bin` | DB `postgis_34_sample`, the Tiger geocoder + address_standardizer extensions |
| curl | `C:\WINDOWS\system32\curl.exe` | **used instead of wget** (see gotchas) |
| 7-Zip | `C:\Program Files\7-Zip\7z.exe` | unzip + `7z t` integrity checks |
| JDK | `C:\jdk-11.0.24+8` (set `JAVA_HOME`) | Java 11; runs JasperReports + javac |
| Maven | `C:\apache-maven-3.9.9\bin\mvn.cmd` | built JasperReports from source |
| JasperReports 7.0.6 runtime | `C:\Users\rgorsuch\jasperreports-lib\` | 37 jars (core, pdf, openpdf, PG JDBC driver, deps) |
| JasperReports 7.0.6 source | `C:\Users\rgorsuch\jasperreports-7.0.6\` | Maven source project (extracted from the -project.zip) |

## 3. GOTCHAS (the expensive-to-rediscover lessons)

1. **wget is firewall-blocked.** `winget install wget` fails — its source `eternallybored.org` is
   DNS-blocked by the corporate firewall. **Use the built-in `curl.exe`.** The TIGER loader scripts
   were rewritten to use `curl --location --fail --retry 3 --create-dirs -o "<host\path>" "<url>"`
   (rebuilds wget --mirror's directory tree).
2. **Census downloads silently corrupt.** curl exits 0 (HTTP 200) but bytes can be truncated/bad
   (this killed PLACE + TRACT on the first run). **Always validate every download with `7z t` and retry.**
   `load_tiger_TX.bat` has a `:getverified` subroutine that does this; the PS1 loaders use a `Get-Verified` function.
3. **Cloudflare can cache a WAF "Request Rejected" page** (247-byte HTML, HTTP 200, `cf-cache-status: HIT`)
   for a specific census URL (hit on Nacogdoches `48347` edges). `--fail` won't catch it. **Fix: re-request with a
   cache-buster query string (`?cb=<timestamp>`) + a browser `-A` User-Agent.**
4. **PowerShell mangles Maven `-D` args.** `-Dmaven.test.skip=true` gets split into a bogus lifecycle phase.
   **Pass Maven args after the `--%` stop-parsing token.**
5. **JasperReports 7 has a NEW jrxml format**, NOT backward-compatible with 6.x (Jackson-based loader):
   no XML namespace; root `<jasperReport name=".." language="java" ..>`; `<queryString>`→`<query>`;
   `<reportElement>` removed (x/y/w/h flattened onto `<element kind="..">`); `textAlignment`→`hTextAlign`/`vTextAlign`;
   `<variableExpression>`/`<groupExpression>`→`<expression>`. A 6.x jrxml fails JR7's CLI loader (open in
   Jaspersoft Studio to auto-upgrade, or use the `_jr7` version here).
6. **JR 7 PDF export is a separate module** (`jasperreports-pdf` / OpenPDF) — core alone throws
   "Missing JasperReports PDF Extension". Build `ext/pdf` too.
7. **`usa_states`** was SRID 0 (undefined) → fixed to **4269** (NAD83, matches TIGER). It and two other
   former-`public` data tables now live in schema **`tiger`** (`tiger.usa_states` etc.). `public` holds only
   PostGIS/extension objects — do NOT move those.

## 4. Scripts (`scripts\`)

All use absolute paths; safe to run from anywhere. Run `.bat` from `cmd.exe`, `.ps1` via `powershell -File`.

| Script | Purpose |
|--------|---------|
| `load_tiger_nation.bat` | One-time: load national STATE + COUNTY lookup tables. Run first. |
| `load_tiger_TX.bat` | Full statewide TX loader (all layers, all 254 counties). Has the `:getverified` CRC-verify+retry fix and curl. Long run. |
| `load_geocode_travis.bat` | Loads PLACE (statewide) + EDGES/FEATNAMES/ADDR for Travis County only (fast demo). |
| `load_geocode_faces_zip.bat` | Loads Travis FACES + builds the zip lookup tables (needed for geocoding). |
| `load_metros.ps1` | Verified loader for 16 metro counties (faces/featnames/edges/addr), idempotent. |
| `load_remaining.ps1` | Verified loader for ALL remaining counties; **idempotent** (skips counties already in `tx_edges`). |
| `test_verify.bat` | Standalone test of the download-verify-retry subroutine. |

## 5. Reports (`report\`)

- `tx_density_blockgroup_report.jrxml` — JasperReports **6.x** format (open in Jaspersoft Studio to auto-upgrade).
- `tx_density_blockgroup_report_jr7.jrxml` — native **JR 7** format; compiles with the built library.
- `tx_density_blockgroup_report_jr7.jasper` — compiled report.
- `postgis_34_sample.xml` — Jaspersoft Studio JDBC data adapter (needs the PostgreSQL driver on its classpath).
- `CompileReport.java` / `FillReport.java` — CLI compile + fill/export harnesses.

**Build the JasperReports library (once):**
```
set JAVA_HOME=C:\jdk-11.0.24+8
mvn --% -f C:\Users\rgorsuch\jasperreports-7.0.6\pom.xml -pl core,ext/pdf -am -Dmaven.test.skip=true -Dmaven.javadoc.skip=true -B install
mvn --% -f C:\Users\rgorsuch\jasperreports-7.0.6\core\pom.xml  dependency:copy-dependencies -DoutputDirectory=C:\Users\rgorsuch\jasperreports-lib -DincludeScope=runtime
mvn --% -f C:\Users\rgorsuch\jasperreports-7.0.6\ext\pdf\pom.xml dependency:copy-dependencies -DoutputDirectory=C:\Users\rgorsuch\jasperreports-lib -DincludeScope=runtime
copy core\target\jasperreports-7.0.6.jar + ext\pdf\target\jasperreports-pdf-7.0.6.jar into jasperreports-lib\
:: PostgreSQL JDBC driver: curl https://repo1.maven.org/maven2/org/postgresql/postgresql/42.7.4/postgresql-42.7.4.jar -> jasperreports-lib\
```

**Compile + render to PDF** (run from `report\`):
```
set CP=C:\Users\rgorsuch\jasperreports-lib\*
set PGPASSWORD=<your local password>   :: FillReport reads PGPASSWORD from the environment
"C:\jdk-11.0.24+8\bin\javac.exe" -cp "%CP%" CompileReport.java FillReport.java
"C:\jdk-11.0.24+8\bin\java.exe" -Dnet.sf.jasperreports.compiler.class=net.sf.jasperreports.engine.design.JRJavacCompiler -cp "%CP%;." CompileReport tx_density_blockgroup_report_jr7.jrxml
"C:\jdk-11.0.24+8\bin\java.exe" -cp "%CP%;." FillReport tx_density_blockgroup_report_jr7.jasper ..\output\tx_density_blockgroup_report.pdf
```

## 6. Maps (`maps\`)

Self-contained HTML (Leaflet + CDN). Open directly in a browser.

| File | Shows |
|------|-------|
| `tx_population_heatmap.html` | Statewide pop heatmap, 2 km grid (64,722 cells) |
| `tx_population_heatmap_blocks.html` | Full block-detail heatmap (449k blocks; heavy) |
| `houston_population_heatmap.html` | Houston metro, 500 m grid |
| `tx_density_choropleth.html` | Density choropleth by census tract (6,896) |
| `tx_density_choropleth_blockgroup.html` | Density choropleth by block group (18,638) |
| `geocode_result.html` / `geocode_houston.html` | Single geocoded address pins |

## 7. Rebuild order from scratch

1. `load_tiger_nation.bat` (national lookups).
2. `load_remaining.ps1` (verified statewide county load; or `load_tiger_TX.bat`). Sweep the log for
   `DOWNLOAD FAILED (skipped)` and repair those files with the cache-buster+UA trick.
3. Build the JasperReports library (§5), compile + fill the report.
4. Regenerate maps as needed (queries embedded in session history; data in `tiger_data.tx_*`).

## 8. Useful geocode test

```sql
SELECT g.rating, ST_X(g.geomout) lon, ST_Y(g.geomout) lat, pprint_addy(g.addy)
FROM geocode('901 Bagby St, Houston, TX 77002', 1) AS g;
```
