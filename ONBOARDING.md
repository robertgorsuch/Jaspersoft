# Onboarding — Texas PostGIS Geocoder & Population Reporting

This project builds a **statewide Texas address geocoder** on PostGIS, a set of **population‑density
maps**, and a **JasperReports 7** report — all over a single PostgreSQL database.

## Get oriented in 5 minutes

- **Database:** `postgis_34_sample` on `localhost:5432` (user/pw `postgres` / `<your local password>`), PostgreSQL 14 + PostGIS 3.4.
  The PostGIS **Tiger geocoder** is loaded for **all 254 Texas counties**.
- **Try it:**
  ```sql
  SELECT g.rating, pprint_addy(g.addy)
  FROM geocode('1100 Congress Ave, Austin, TX 78701', 1) AS g;   -- rating 0, exact match
  ```
- **Project files:** `C:\Users\rgorsuch\tx-geocoder\` → `scripts\` (loaders), `report\` (JasperReports),
  `maps\` (Leaflet HTML), `output\` (PDF, exports). **Read `tx-geocoder\RUNBOOK.md` for the full reference.**

## The 5 things that will bite you (gotchas)

1. **Use `curl.exe`, not wget** — wget's installer source is firewall‑blocked here.
2. **Always verify downloads with `7z t` + retry** — the census CDN returns silently corrupt zips (HTTP 200).
3. **A WAF "Request Rejected" page can be Cloudflare‑cached** for a URL → re‑request with `?cb=<timestamp>` + a browser User‑Agent.
4. **JasperReports 7 jrxml ≠ 6.x** — new Jackson format (`<query>` not `<queryString>`, no `<reportElement>`). Use the `_jr7` file or let Jaspersoft Studio auto‑upgrade. PDF export needs the separate `jasperreports-pdf` module.
5. **In PowerShell, pass Maven `-D…` args after `--%`** or they get mangled.

## Key prerequisites

PostgreSQL 14 · JDK 11 (`C:\jdk-11.0.24+8`) · Maven 3.9 · 7‑Zip · curl. JasperReports 7.0.6 runtime is
prebuilt at `C:\Users\rgorsuch\jasperreports-lib\`. Census TIGER data staging lives in `C:\gisdata`.

## Common tasks

- **Geocode / map an address:** see `maps\geocode_*.html` for examples; `geocode()` in SQL.
- **Rebuild the geocoder:** `scripts\load_tiger_nation.bat` then `scripts\load_remaining.ps1` (idempotent, verified).
- **Render the report PDF:** see RUNBOOK §5 (compile `report\*_jr7.jrxml` → fill against the DB → PDF).

Full details, rebuild order, and exact commands: **`tx-geocoder\RUNBOOK.md`**.
