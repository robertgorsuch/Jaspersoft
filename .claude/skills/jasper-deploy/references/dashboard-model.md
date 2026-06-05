# JRS 10 dashboard model (reverse-engineered)

A JasperReports Server dashboard (`resourceType=dashboard`) is a small,
deterministic model: a descriptor `.xml` plus three companion files in its
`_files` folder. `gen_dashboard.py` synthesizes all four from a manifest;
`compose_dashboard.ps1` wraps them in an importable archive. This file documents
the shapes so the generator isn't the only source of truth.

## Why import, not PUT
PUTting a hand-built model to `/rest_v2/resources` stores it (201) but the JRS 10
client renders it **blank** — the designer/import broker does extra work on save
that a raw PUT skips. The **import** service reproduces that work, so a
synthesized archive that matches a designer export renders correctly. Always go
through `compose_dashboard.ps1` (export real dashlets → inject → import), never a
direct PUT. Re-zip with **forward-slash** entries — the Java importer silently
ignores back-slash paths.

## Descriptor (`<name>.xml`)
`<dashboardModelResource>` with `<folder>`, `<name>`, `<label>`, a `<foundation>`
naming the three companion resources (`layout`/`wiring`/`components`), a
`<resourceDescriptor type="reportUnit">` + `<resource><uri>` per **report** tile
(text/image tiles are NOT listed), and three `<localResource>` blocks for the
companion files (`wiring.data` json, `layout` html, `components.data`
dashboardComponent).

## components.data (JSON array)
Element 0 is the `dashboardProperties` singleton (canvas color, margins, refresh,
title bar). Then one object per dashlet. The **component id** = `re.sub(r'[^0-9A-Za-z]','_', label)` (must be unique); `layout` and `wiring` reference it.

- **report tile** — `{"type":"reportUnit","id","name","label","resource":"<uri>","dataSourceUri":"<uri>","scaleToFit":"width","showTitleBar":true, ...}`
- **text tile** — `{"type":"text","id","name","label":"Text","text","alignment","bold","italic","underline","font","size","color":"rgba(..)","backgroundColor","verticalAlignment","scaleToFit":"height","showDashletBorders","parameters":[],"toolbar":null}`
- **image tile** — `{"type":"image","id","name","label":"Image","url":"repo:/path or http://..","scaleToFit":"container","showTitleBar":false,"showDashletBorders","dashletHyperlinkTarget","parameters":[],"outputParameters":[]}`

## layout (HTML)
One `<div>` per component on a **40-wide** grid:
`<div data-componentId='ID' data-x='..' data-y='..' data-width='..' data-height='..'></div>`.

## wiring.data (JSON array)
Two base events broadcast from the properties singleton to every tile:
`@init`→each `ID:@refresh`, and `@applyParams`→each `ID:@applyParams`. Extra
producer→consumer events (cross-dashlet filtering) can be appended — the manifest
`"wiring":[{"producer":"A:out","consumers":["B:param"]}]` passes them through.

## What is NOT synthesizable (designer-only)
- **filterGroup + inputControl tiles** — the interactive filter UI depends on
  designer-generated temp resources (`tmpAdv_*_files`, `ownerResourceId`), so a
  real filter group must be authored in the designer.
- **Ad hoc views** (`adhocDataView`) — a large opaque `<unifiedState>` (chart
  state, filters, columns) on top of a **Domain** semantic layer (`schema.xml`)
  and an auto-generated topic jrxml. Author in the Ad Hoc Designer; promote with
  `export_resource.ps1` / `import_resource.ps1` / `promote.ps1`.
