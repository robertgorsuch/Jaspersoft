# Onboarding — Texas PostGIS Geocoder & Population Reporting

This project builds a **statewide Texas address geocoder** on PostGIS, a set of **population‑density
maps**, a **JasperReports 7** report — all over a single PostgreSQL database — and a **`jasper-deploy`
skill** that scripts the whole JasperReports design→deploy→verify pipeline (and composes dashboards)
against a local **JasperReports Server 10**.

## Get oriented in 5 minutes

- **Database:** `postgis_34_sample` on `localhost:5432` (user/pw `postgres` / `<your local password>`), PostgreSQL 14 + PostGIS 3.4.
  The PostGIS **Tiger geocoder** is loaded for **all 254 Texas counties**.
- **Try it:**
  ```sql
  SELECT g.rating, pprint_addy(g.addy)
  FROM geocode('1100 Congress Ave, Austin, TX 78701', 1) AS g;   -- rating 0, exact match
  ```
- **Project files:** `C:\Users\rgorsuch\tx-geocoder\` → `scripts\` (loaders), `report\` (JasperReports +
  `report\foodmart\` deployables), `.claude\skills\jasper-deploy\` (the automation skill),
  `maps\` (Leaflet HTML), `output\` (PDF, exports). **Read `tx-geocoder\RUNBOOK.md` for the full reference.**
- **JasperReports Server:** PRO at `http://localhost:8081/jasperserver-pro` (`superuser`/`superuser`).
  The `jasper-deploy` skill (its `SKILL.md`) automates scaffolding reports from SQL, deploying them,
  verifying renders, and composing dashboards from a JSON manifest.

## The 5 things that will bite you (gotchas)

1. **Use `curl.exe`, not wget** — wget's installer source is not reachable from this environment.
2. **Always verify downloads with `7z t` + retry** — the census CDN returns silently corrupt zips (HTTP 200).
3. **A WAF "Request Rejected" page can be Cloudflare‑cached** for a URL → re‑request with `?cb=<timestamp>` + a browser User‑Agent.
4. **JasperReports 7 jrxml ≠ 6.x** — new Jackson format (`<query>` not `<queryString>`, no `<reportElement>`). Use the `_jr7` file or let Jaspersoft Studio auto‑upgrade. PDF export needs the separate `jasperreports-pdf` module.
5. **In PowerShell, pass Maven `-D…` args after `--%`** or they get mangled.
6. **JRS report queries must start with `SELECT`** — a leading `WITH` (CTE) compiles locally but the
   server rejects it at fill time (`deploy_report.ps1` now lints+blocks it; push CTEs into a `FROM` subquery).
7. **JRS dashboards: import, don't PUT** — a hand-built model PUT to `/rest_v2/resources` renders blank;
   `compose_dashboard.ps1` imports a designer-equivalent archive instead. Reports that are dashlets are
   modification-locked (`403 resource.in.use`) until the owning dashboard is removed.

## Key prerequisites

PostgreSQL 14 · JDK 11 (`C:\jdk-11.0.24+8`) · Maven 3.9 · 7‑Zip · curl. JasperReports 7.0.6 runtime is
prebuilt at `C:\Users\rgorsuch\jasperreports-lib\`. Census TIGER data staging lives in `C:\gisdata`.

## Common tasks

- **Geocode / map an address:** see `maps\geocode_*.html` for examples; `geocode()` in SQL.
- **Rebuild the geocoder:** `scripts\load_tiger_nation.bat` then `scripts\load_remaining.ps1` (idempotent, verified).
- **Render the report PDF:** see RUNBOOK §5 (compile `report\*_jr7.jrxml` → fill against the DB → PDF).
- **Deploy reports / build a dashboard (jasper-deploy skill):** `$env:PGPASSWORD="postgres"` then
  `& .\.claude\skills\jasper-deploy\scripts\build_dashlets.ps1 -Manifest report\foodmart\dashboard.json -Compose`.
  After editing any skill script, run `…\scripts\smoke_test.ps1` as the end-to-end check. See RUNBOOK §9.

Full details, rebuild order, and exact commands: **`tx-geocoder\RUNBOOK.md`** (§9 for the jasper-deploy skill).
