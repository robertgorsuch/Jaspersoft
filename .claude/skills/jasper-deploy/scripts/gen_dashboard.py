#!/usr/bin/env python3
"""Synthesize a JasperReports Server dashboard import archive from a manifest.

JRS 10 dashboards cannot be composed by PUTting a model to /rest_v2/resources
(the server stores it but the client renders it blank). The *supported* path is
export/import: the designer's own export archive re-imports and renders
identically. This script generates a byte-compatible export archive
programmatically -- the dashboard descriptor (.xml) plus the three companion
files the designer produces (components.data / layout / wiring.data) -- so a
dashboard can be composed from a manifest and imported with import_resource.ps1,
no designer needed.

The model shape was reverse-engineered from a real designer export (every field
below matches what the JRS 10 designer writes). The dashlets (reportUnits) must
already be deployed; they are referenced by repository URI.

Manifest (JSON):
{
  "folder": "/reports/foodmart",          # repository folder to hold the dashboard
  "name":   "foodmart_kpi_dashboard",      # resource name (no spaces)
  "label":  "Foodmart KPI Dashboard",      # display label
  "dashlets": [                            # one per deployed report, placed on a 40-wide grid
    {"resource": "/reports/foodmart/foodmart_yoy_sales",
     "label": "Year-over-Year Sales (1997 vs 1998)",
     "x": 0, "y": 0, "width": 22, "height": 10},
    ...
  ]
}

Emits a .zip ready for import_resource.ps1. With --auto-grid, dashlet x/y/width/
height are computed automatically (two columns) when omitted.
"""
import argparse
import json
import os
import re
import sys
import zipfile
from datetime import datetime, timezone


def component_id(label: str) -> str:
    """Designer rule: every non-alphanumeric char in the label -> '_'."""
    return re.sub(r"[^0-9A-Za-z]", "_", label)


def iso_now() -> str:
    # local time with offset, milliseconds -- matches the designer's format
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="milliseconds")


# --- the three companion files ----------------------------------------------
def build_components(dashlets) -> str:
    props = {
        "id": "DashboardProperties", "type": "dashboardProperties",
        "name": "DashboardProperties", "autoRefresh": False,
        "refreshInterval": 5, "refreshIntervalUnit": "minute",
        "showDashletBorders": True, "showExportButton": False,
        "showPrintButton": False, "dashletMargin": 5, "dashletPadding": 5,
        "dashletFilterShowPopup": False, "useFixedSize": False,
        "fixedWidth": 1280, "fixedHeight": 800, "canvasColor": "#ffffff",
        "titleBarColor": "rgba(0, 0, 0, 0)", "titleTextColor": "#454545",
    }
    arr = [props]
    for d in dashlets:
        cid = d["cid"]
        kind = d.get("kind", "report")
        if kind == "text":
            arr.append({
                "type": "text", "label": "Text", "id": cid, "name": cid,
                "text": d.get("text", ""), "alignment": d.get("align", "left"),
                "bold": bool(d.get("bold", False)), "italic": bool(d.get("italic", False)),
                "underline": bool(d.get("underline", False)),
                "font": d.get("font", "Arial"), "size": int(d.get("size", 12)),
                "color": d.get("color", "rgba(0, 0, 0, 1)"),
                "backgroundColor": d.get("background", "rgba(0, 0, 0, 0)"),
                "scaleToFit": "height", "showDashletBorders": bool(d.get("border", False)),
                "borderColor": "rgb(208, 208, 208)",
                "verticalAlignment": d.get("valign", "top"),
                "exposeOutputsToFilterManager": False, "dashletHyperlinkTarget": "",
                "parameters": [], "toolbar": None,
            })
        elif kind == "image":
            arr.append({
                "type": "image", "label": "Image", "id": cid, "name": cid,
                "url": d["url"], "scaleToFit": d.get("scaleToFit", "container"),
                "showTitleBar": False, "showRefreshButton": False,
                "showMaximizeButton": False, "showDashletBorders": bool(d.get("border", False)),
                "borderColor": "rgba(208, 208, 208, 1)",
                "exposeOutputsToFilterManager": False,
                "dashletHyperlinkTarget": d.get("linkTarget", "Self"),
                "parameters": [], "outputParameters": [],
            })
        else:  # report
            arr.append({
                "type": "reportUnit", "label": d["label"], "resource": d["resource"],
                "exposeOutputsToFilterManager": False, "dashletHyperlinkTarget": "",
                "id": cid, "name": d["label"], "scaleToFit": "width",
                "autoRefresh": False, "refreshInterval": 5,
                "refreshIntervalUnit": "minute", "showTitleBar": True,
                "showExportButton": False, "showPrintButton": False,
                "showRefreshButton": False, "showMaximizeButton": True,
                "showBackButton": True, "dataSourceUri": d["resource"],
                "showVizSelectorIcon": False, "outputParameters": [],
                "parameters": [], "showVizSelector": False,
            })
    return json.dumps(arr, separators=(",", ":"))


def build_layout(dashlets) -> str:
    return "".join(
        f"<div data-componentId='{d['cid']}' data-x='{d['x']}' data-y='{d['y']}' "
        f"data-width='{d['width']}' data-height='{d['height']}'></div>"
        for d in dashlets)


def build_wiring(dashlets, extra=None) -> str:
    def event(name):
        return {
            "name": name, "producer": f"DashboardProperties:{name}",
            "component": "DashboardProperties",
            "consumers": [{"consumer": f"{d['cid']}:"
                           + ("@refresh" if name == "@init" else "@applyParams")}
                          for d in dashlets],
        }
    events = [event("@init"), event("@applyParams")]
    # optional cross-dashlet wiring passthrough: [{producer, consumers:[..]}]
    for w in (extra or []):
        prod = w["producer"]
        events.append({
            "name": prod.split(":")[-1], "producer": prod,
            "component": prod.split(":")[0],
            "consumers": [{"consumer": c} for c in w.get("consumers", [])],
        })
    return json.dumps(events, separators=(",", ":"))


# --- archive descriptors -----------------------------------------------------
def build_descriptor(folder, name, label, dashlets, ts) -> str:
    files_folder = f"{folder}/{name}_files"
    report_dashlets = [d for d in dashlets if d.get("kind", "report") == "report"]
    rds = "".join(
        f"    <resourceDescriptor>\n        <type>reportUnit</type>\n"
        f"        <id>{d['resource']}</id>\n    </resourceDescriptor>\n"
        for d in report_dashlets)
    res_uris = "".join(
        f"    <resource>\n        <uri>{d['resource']}</uri>\n    </resource>\n"
        for d in report_dashlets)

    def local(data_file, rname, ftype, xsitype, ver):
        return (
            f"    <resource>\n"
            f"        <localResource\n"
            f'            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"\n'
            f'            exportedWithPermissions="false" dataFile="{data_file}" '
            f'xsi:type="{xsitype}">\n'
            f"            <folder>{files_folder}</folder>\n"
            f"            <name>{rname}</name>\n"
            f"            <version>{ver}</version>\n"
            f"            <label>{rname}</label>\n"
            f"            <creationDate>{ts}</creationDate>\n"
            f"            <updateDate>{ts}</updateDate>\n"
            f"            <fileType>{ftype}</fileType>\n"
            f"        </localResource>\n"
            f"    </resource>\n")

    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<dashboardModelResource exportedWithPermissions="true">\n'
        f"    <folder>{folder}</folder>\n"
        f"    <name>{name}</name>\n"
        f"    <version>0</version>\n"
        f"    <label>{label}</label>\n"
        f"    <creationDate>{ts}</creationDate>\n"
        f"    <updateDate>{ts}</updateDate>\n"
        "    <defaultFoundation>default</defaultFoundation>\n"
        "    <foundation>\n"
        "        <id>default</id>\n"
        "        <layout>layout</layout>\n"
        "        <wiring>wiring</wiring>\n"
        "        <components>components</components>\n"
        "    </foundation>\n"
        "    <resourceDescriptor>\n        <type>wiring</type>\n        <id>wiring</id>\n    </resourceDescriptor>\n"
        "    <resourceDescriptor>\n        <type>layout</type>\n        <id>layout</id>\n    </resourceDescriptor>\n"
        "    <resourceDescriptor>\n        <type>components</type>\n        <id>components</id>\n    </resourceDescriptor>\n"
        f"{rds}"
        + local("wiring.data", "wiring", "json", "fileResource", 1)
        + local("layout", "layout", "html", "contentResource", 2)
        + local("components.data", "components", "dashboardComponent", "fileResource", 1)
        + res_uris
        + "</dashboardModelResource>\n"
    )


def build_folder_xml(path, ts) -> str:
    """A repository folder descriptor (.folder.xml) for `path`."""
    parent = path.rsplit("/", 1)[0] or "/"
    nm = path.rsplit("/", 1)[1]
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<folder exportedWithPermissions="true">\n'
        f"    <parent>{parent}</parent>\n"
        f"    <name>{nm}</name>\n"
        f"    <label>{nm}</label>\n"
        f"    <creationDate>{ts}</creationDate>\n"
        f"    <updateDate>{ts}</updateDate>\n"
        "</folder>\n"
    )


def ancestor_folders(folder):
    """['/reports', '/reports/foodmart'] for folder='/reports/foodmart'."""
    parts = [p for p in folder.split("/") if p]
    return ["/" + "/".join(parts[: i + 1]) for i in range(len(parts))]


def build_index(folder, name) -> str:
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        "<export>"
        '<module id="repositoryResources">'
        f"<resource>{folder}/{name}</resource>"
        "</module>"
        '<module id="favorites"/>'
        '<property name="pathProcessorId" value="zip"/>'
        '<property name="rootTenantId" value="organizations"/>'
        "</export>\n"
    )


def main():
    ap = argparse.ArgumentParser(description="Synthesize a JRS dashboard import archive.")
    ap.add_argument("--manifest", required=True, help="dashboard manifest JSON")
    ap.add_argument("--out", required=True, help="output .zip path")
    ap.add_argument("--auto-grid", action="store_true",
                    help="compute x/y/width/height for any dashlet missing them")
    args = ap.parse_args()

    with open(args.manifest, encoding="utf-8-sig") as f:  # tolerate a UTF-8 BOM
        m = json.load(f)
    folder = m["folder"].rstrip("/")
    name = m["name"]
    label = m.get("label", name)
    dashlets = m["dashlets"]
    if not dashlets:
        sys.stderr.write("ERROR: manifest has no dashlets\n")
        sys.exit(2)

    # normalize each dashlet: kind (report|text|image), a stable component id,
    # and -- for report tiles -- the repository URI + display label. report
    # dashlets may be given as {resource,label} or {name,title}; text/image
    # tiles need no resource.
    used_ids = set()
    for i, d in enumerate(dashlets):
        kind = d.setdefault("kind", "report")
        if kind == "report":
            d.setdefault("resource", f"{folder}/{d['name']}" if "name" in d else None)
            if not d.get("resource"):
                sys.stderr.write(f"ERROR: report dashlet needs 'resource' or 'name': {d}\n")
                sys.exit(2)
            d.setdefault("label", d.get("title") or d["resource"].rsplit("/", 1)[-1])
        else:
            if kind == "image" and not d.get("url"):
                sys.stderr.write(f"ERROR: image dashlet needs 'url': {d}\n"); sys.exit(2)
            d.setdefault("label", d.get("name") or kind.capitalize())
        cid = d.get("id") or component_id(d.get("label") or kind)
        while cid in used_ids:                      # ensure uniqueness
            cid = f"{cid}_{i}"
        used_ids.add(cid)
        d["cid"] = cid

    if args.auto_grid:
        # pack into `cols` columns (default 2) across the 40-wide grid; text/image
        # tiles default shorter than report tiles, and stack row by row.
        cols = int(m.get("cols", 2))
        cw = max(1, 40 // cols)
        col_y = [0] * cols
        for i, d in enumerate(dashlets):
            defh = 4 if d["kind"] == "text" else (8 if d["kind"] == "image" else 10)
            d.setdefault("width", cw)
            d.setdefault("height", defh)
            c = i % cols
            d.setdefault("x", c * cw)
            d.setdefault("y", col_y[c])
            col_y[c] = d["y"] + d["height"]
    missing = [d.get("label", "?") for d in dashlets
               if any(k not in d for k in ("x", "y", "width", "height"))]
    if missing:
        sys.stderr.write("ERROR: these dashlets lack x/y/width/height "
                         f"(use --auto-grid): {missing}\n")
        sys.exit(2)

    ts = iso_now()
    base = f"resources{folder}/{name}"
    files_base = f"resources{folder}/{name}_files"
    entries = {
        "index.xml": build_index(folder, name),
        f"{base}.xml": build_descriptor(folder, name, label, dashlets, ts),
        f"{files_base}/components.data": build_components(dashlets),
        f"{files_base}/layout": build_layout(dashlets),
        f"{files_base}/wiring.data": build_wiring(dashlets, m.get("wiring")),
    }
    # the folder chain that holds the dashboard must be described or the import
    # broker silently no-ops (reports referenced by URI are resolved in the repo)
    for fpath in ancestor_folders(folder):
        entries[f"resources{fpath}/.folder.xml"] = build_folder_xml(fpath, ts)

    os.makedirs(os.path.dirname(os.path.abspath(args.out)) or ".", exist_ok=True)
    with zipfile.ZipFile(args.out, "w", zipfile.ZIP_DEFLATED) as z:
        for arcname, content in entries.items():
            z.writestr(arcname, content)

    print(f"OK: wrote {args.out} ({len(dashlets)} dashlets) for {folder}/{name}")
    for d in dashlets:
        tgt = d.get("resource") or d.get("url") or f"({d['kind']})"
        print(f"    [{d['x']:>2},{d['y']:>2} {d['width']}x{d['height']}] "
              f"{d['cid']:<40} {tgt}")


if __name__ == "__main__":
    main()
