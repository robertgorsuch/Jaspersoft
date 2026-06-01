#!/usr/bin/env python3
"""Scaffold a JasperReports 7 (JR7-native) .jrxml from a SQL query.

Introspects the query's result columns by creating a TEMP VIEW over it and
reading information_schema.columns (via psql), maps PostgreSQL types to Java
field classes, and emits a tabular JR7 report: title, columnHeader, detail
band, and pageFooter. The output mirrors the idioms in the known-good
tx_density_blockgroup_report_jr7.jrxml so it compiles with JasperReports 7.0.6.

JR7 is NOT 6.x-compatible: no XML namespace, root is <jasperReport name=..>,
<query> (not <queryString>), and elements use <element kind=".." x= y= ..>
with x/y/width/height flattened on (no <reportElement>).

psql must be on PATH; the DB password is read from the PGPASSWORD env var.
"""
import argparse
import csv
import io
import os
import subprocess
import sys
from xml.sax.saxutils import escape

# --- PostgreSQL (udt_name) -> Java field class -------------------------------
UDT_TO_JAVA = {
    "int2": "java.lang.Integer",
    "int4": "java.lang.Integer",
    "int8": "java.lang.Long",
    "numeric": "java.math.BigDecimal",
    "float4": "java.lang.Double",
    "float8": "java.lang.Double",
    "bool": "java.lang.Boolean",
    "date": "java.sql.Date",
    "timestamp": "java.sql.Timestamp",
    "timestamptz": "java.sql.Timestamp",
    "time": "java.sql.Time",
    "timetz": "java.sql.Time",
}

NUMERIC_JAVA = {"java.lang.Integer", "java.lang.Long"}
DECIMAL_JAVA = {"java.math.BigDecimal", "java.lang.Double"}


def java_class(udt_name: str) -> str:
    return UDT_TO_JAVA.get(udt_name.lower(), "java.lang.String")


def display_pattern(jclass: str):
    if jclass in NUMERIC_JAVA:
        return "#,##0"
    if jclass in DECIMAL_JAVA:
        return "#,##0.00"
    if jclass == "java.sql.Date":
        return "yyyy-MM-dd"
    if jclass == "java.sql.Timestamp":
        return "yyyy-MM-dd HH:mm"
    return None


def is_right_aligned(jclass: str) -> bool:
    return jclass in NUMERIC_JAVA or jclass in DECIMAL_JAVA


def label_for(col: str) -> str:
    """county_pop -> 'County Pop'."""
    return " ".join(w.capitalize() for w in col.replace("_", " ").split())


# --- column introspection via psql -------------------------------------------
def introspect(query: str, host, port, user, db) -> list:
    """Return [(column_name, udt_name), ...] for the query's result set."""
    sql = query.strip().rstrip(";")
    script = (
        "CREATE TEMP VIEW _jr_scaffold AS\n"
        f"{sql}\n;\n"
        # scope to the temp schema so a same-named relation elsewhere can't
        # inject duplicate columns into the field list
        r"\copy (SELECT column_name, udt_name FROM information_schema.columns "
        "WHERE table_name = '_jr_scaffold' AND table_schema LIKE 'pg_temp%' "
        "ORDER BY ordinal_position) TO STDOUT WITH (FORMAT csv)\n"
    )
    cmd = ["psql", "-h", host, "-p", str(port), "-U", user, "-d", db,
           "-v", "ON_ERROR_STOP=1", "-q", "-X", "-f", "-"]
    proc = subprocess.run(cmd, input=script, capture_output=True, text=True)
    if proc.returncode != 0:
        sys.stderr.write("psql introspection failed:\n" + proc.stderr + "\n")
        sys.exit(2)
    cols = []
    for row in csv.reader(io.StringIO(proc.stdout)):
        if len(row) >= 2:
            cols.append((row[0], row[1]))
    if not cols:
        sys.stderr.write("No columns detected for the query.\n")
        sys.exit(2)
    return cols


# --- width layout ------------------------------------------------------------
def layout_widths(cols, total):
    """Weighted column widths that are all positive and sum to exactly `total`.

    A fixed 40px minimum would overflow `total` once there are more than
    total/40 columns, pushing the rounding remainder negative; instead the
    minimum is capped to what actually fits, and the rounding remainder is
    spread across columns (never dumped onto one), so no width goes <= 0.
    """
    n = len(cols)
    weights = [1.0 if is_right_aligned(java_class(udt)) else 1.6 for _name, udt in cols]
    s = sum(weights)
    min_w = max(1, min(40, total // n))            # a floor that always fits
    raw = [max(min_w, int(total * w / s)) for w in weights]

    # nudge one px at a time (up or down) until the widths sum to exactly
    # `total`, never letting any column drop below min_w
    diff = total - sum(raw)
    step = 1 if diff > 0 else -1
    i = 0
    while diff != 0:
        idx = i % n
        if not (step < 0 and raw[idx] <= min_w):
            raw[idx] += step
            diff -= step
        i += 1
    return raw


# --- XML emission ------------------------------------------------------------
def el_static(x, y, w, h, text, *, fontsize=9.0, bold=False, forecolor=None,
              halign=None, valign="Middle"):
    attrs = [f'kind="staticText"', f'x="{x}"', f'y="{y}"',
             f'width="{w}"', f'height="{h}"', f'fontSize="{fontsize}"']
    if bold:
        attrs.append('bold="true"')
    if forecolor:
        attrs.append(f'forecolor="{forecolor}"')
    if halign:
        attrs.append(f'hTextAlign="{halign}"')
    if valign:
        attrs.append(f'vTextAlign="{valign}"')
    return (f'\t\t<element {" ".join(attrs)}>'
            f'<text><![CDATA[{text}]]></text></element>')


def el_textfield(x, y, w, h, expr, *, fontsize=8.0, halign=None,
                 valign="Middle", pattern=None):
    attrs = [f'kind="textField"', f'x="{x}"', f'y="{y}"',
             f'width="{w}"', f'height="{h}"', f'fontSize="{fontsize}"']
    if halign:
        attrs.append(f'hTextAlign="{halign}"')
    if valign:
        attrs.append(f'vTextAlign="{valign}"')
    if pattern:
        attrs.append(f'pattern="{pattern}"')
    return (f'\t\t<element {" ".join(attrs)}>'
            f'<expression><![CDATA[{expr}]]></expression></element>')


# --- chart support (JFreeChart, community) -----------------------------------
# maps --chart value -> (jrxml chartType attribute, dataset kind)
CHART_TYPES = {
    "pie": ("pie", "pie"),
    "pie3d": ("pie3D", "pie"),
    "bar": ("bar", "category"),
    "bar3d": ("bar3D", "category"),
    "line": ("line", "category"),
    "area": ("area", "category"),
    "stackedbar": ("stackedBar", "category"),
}


def first_text_col(cols):
    for name, udt in cols:
        if java_class(udt) == "java.lang.String":
            return name
    return cols[0][0]


def first_numeric_col(cols):
    for name, udt in cols:
        jc = java_class(udt)
        if jc in NUMERIC_JAVA or jc in DECIMAL_JAVA:
            return name
    return None


def build_chart(chart, cat, val, series, *, width, y, height):
    """Return jrxml lines for a JFreeChart <element kind="chart">."""
    chart_type, ds_kind = CHART_TYPES[chart]
    o = [f'\t\t<element kind="chart" chartType="{chart_type}" x="0" y="{y}" '
         f'width="{width}" height="{height}" evaluationTime="Report">']
    if ds_kind == "pie":
        o.append('\t\t\t<dataset kind="pie">')
        o.append('\t\t\t\t<series>')
        o.append(f'\t\t\t\t\t<keyExpression><![CDATA[$F{{{cat}}}]]></keyExpression>')
        o.append(f'\t\t\t\t\t<valueExpression><![CDATA[$F{{{val}}}]]></valueExpression>')
        o.append('\t\t\t\t</series>')
        o.append('\t\t\t</dataset>')
        o.append('\t\t\t<plot labelFormat="{0}: {2}" legendLabelFormat="{0} ({2})"/>')
    else:
        o.append('\t\t\t<dataset kind="category">')
        o.append('\t\t\t\t<series>')
        if series:
            o.append(f'\t\t\t\t\t<seriesExpression><![CDATA[$F{{{series}}}]]></seriesExpression>')
        else:
            o.append(f'\t\t\t\t\t<seriesExpression><![CDATA["{escape(label_for(val))}"]]></seriesExpression>')
        o.append(f'\t\t\t\t\t<categoryExpression><![CDATA[$F{{{cat}}}]]></categoryExpression>')
        o.append(f'\t\t\t\t\t<valueExpression><![CDATA[$F{{{val}}}]]></valueExpression>')
        o.append('\t\t\t\t</series>')
        o.append('\t\t\t</dataset>')
        o.append('\t\t\t<plot showTickMarks="true" showTickLabels="true"/>')
    o.append('\t\t</element>')
    return o


def build_jrxml(name, title, subtitle, query, cols, *, page_w, page_h,
                margin=20, chart=None, chart_cat=None, chart_val=None,
                chart_series=None, chart_height=300):
    col_w = page_w - 2 * margin
    widths = layout_widths(cols, col_w)
    xs = []
    acc = 0
    for w in widths:
        xs.append(acc)
        acc += w

    out = ['<?xml version="1.0" encoding="UTF-8"?>',
           f'<!-- Generated by jasper-deploy scaffold_jrxml.py. JR7-native (JasperReports 7.0.6). -->',
           f'<jasperReport name="{escape(name)}" language="java" '
           f'pageWidth="{page_w}" pageHeight="{page_h}" columnWidth="{col_w}" '
           f'leftMargin="{margin}" rightMargin="{margin}" '
           f'topMargin="{margin}" bottomMargin="{margin}">']

    # query
    out.append('\t<query language="SQL"><![CDATA[')
    out.append(query.strip().rstrip(";"))
    out.append('\t]]></query>')
    out.append('')

    # fields
    for cname, udt in cols:
        out.append(f'\t<field name="{escape(cname)}" class="{java_class(udt)}"/>')
    out.append('')

    # title band
    title_h = 44 if subtitle else 28
    out.append(f'\t<title height="{title_h}">')
    out.append(el_static(0, 0, col_w, 24, escape(title), fontsize=16.0,
                         bold=True, valign=None))
    if subtitle:
        out.append(el_static(0, 26, col_w, 14, escape(subtitle), fontsize=9.0,
                             forecolor="#666666", valign=None))
    out.append('\t</title>')
    out.append('')

    # column header
    out.append('\t<columnHeader height="18">')
    out.append(f'\t\t<element kind="rectangle" x="0" y="0" width="{col_w}" '
               'height="18" mode="Opaque" backcolor="#34495E" forecolor="#34495E"/>')
    for (cname, udt), x, w in zip(cols, xs, widths):
        jc = java_class(udt)
        halign = "Right" if is_right_aligned(jc) else None
        pad = 6 if halign is None else 0
        out.append(el_static(x + pad, 0, w - pad - (6 if halign else 0), 18,
                             escape(label_for(cname)), fontsize=9.0, bold=True,
                             forecolor="#FFFFFF", halign=halign))
    out.append('\t</columnHeader>')
    out.append('')

    # detail
    out.append('\t<detail>')
    out.append('\t\t<band height="13">')
    for (cname, udt), x, w in zip(cols, xs, widths):
        jc = java_class(udt)
        halign = "Right" if is_right_aligned(jc) else None
        pad = 6 if halign is None else 0
        out.append(el_textfield(x + pad, 0, w - pad - (6 if halign else 0), 13,
                                f'$F{{{cname}}}', fontsize=8.0, halign=halign,
                                pattern=display_pattern(jc)))
    out.append(f'\t\t\t<element kind="line" x="0" y="12" width="{col_w}" '
               'height="1" forecolor="#EEEEEE"/>')
    out.append('\t\t</band>')
    out.append('\t</detail>')
    out.append('')

    # page footer
    out.append('\t<pageFooter height="16">')
    out.append(el_static(0, 2, col_w // 2, 12, escape(title), fontsize=8.0,
                         forecolor="#666666", valign=None))
    out.append(f'\t\t<element kind="textField" x="{col_w - 155}" y="2" '
               'width="120" height="12" forecolor="#666666" fontSize="8.0" '
               'hTextAlign="Right"><expression><![CDATA["Page " + $V{PAGE_NUMBER} + " of"]]>'
               '</expression></element>')
    out.append(f'\t\t<element kind="textField" x="{col_w - 33}" y="2" '
               'width="33" height="12" forecolor="#666666" fontSize="8.0" '
               'evaluationTime="Report"><expression><![CDATA[" " + $V{PAGE_NUMBER}]]>'
               '</expression></element>')
    out.append('\t</pageFooter>')
    out.append('')

    # optional chart in the summary band
    if chart:
        out.append(f'\t<summary height="{chart_height + 20}">')
        out.extend(build_chart(chart, chart_cat, chart_val, chart_series,
                               width=col_w, y=10, height=chart_height))
        out.append('\t</summary>')
        out.append('')

    out.append('</jasperReport>')
    return "\n".join(out) + "\n"


PAGE_SIZES = {"a4": (595, 842), "letter": (612, 792)}


def main():
    ap = argparse.ArgumentParser(description="Scaffold a JR7 jrxml from SQL.")
    ap.add_argument("--name", required=True, help="report name (no spaces)")
    ap.add_argument("--title", help="title band text (default: derived from --name)")
    ap.add_argument("--subtitle", help="optional subtitle line")
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--query", help="SQL query text")
    src.add_argument("--query-file", help="path to a .sql file")
    ap.add_argument("--out", help="output .jrxml path (default: <name>.jrxml)")
    ap.add_argument("--db", default="postgis_34_sample")
    ap.add_argument("--host", default="localhost")
    ap.add_argument("--port", default="5432")
    ap.add_argument("--user", default="postgres")
    ap.add_argument("--page-size", default="a4", choices=list(PAGE_SIZES))
    ap.add_argument("--landscape", action="store_true")
    ap.add_argument("--chart", choices=list(CHART_TYPES),
                    help="also add a JFreeChart in the summary band "
                         "(pie|pie3d|bar|bar3d|line|area|stackedbar)")
    ap.add_argument("--chart-category", help="key/category column (default: first text column)")
    ap.add_argument("--chart-value", help="numeric value column (default: first numeric column)")
    ap.add_argument("--chart-series", help="series column for multi-series category charts")
    ap.add_argument("--chart-height", type=int, default=300)
    args = ap.parse_args()

    if args.query_file:
        with open(args.query_file, encoding="utf-8") as f:
            query = f.read()
    else:
        query = args.query

    if "PGPASSWORD" not in os.environ:
        sys.stderr.write("WARNING: PGPASSWORD not set; psql may prompt or fail.\n")

    cols = introspect(query, args.host, args.port, args.user, args.db)

    w, h = PAGE_SIZES[args.page_size]
    if args.landscape:
        w, h = h, w

    chart_cat = chart_val = None
    if args.chart:
        chart_cat = args.chart_category or first_text_col(cols)
        chart_val = args.chart_value or first_numeric_col(cols)
        if not chart_val:
            sys.stderr.write("ERROR: --chart needs a numeric column; none found "
                             "(use --chart-value).\n")
            sys.exit(2)

    title = args.title or label_for(args.name)
    xml = build_jrxml(args.name, title, args.subtitle, query, cols,
                      page_w=w, page_h=h, chart=args.chart, chart_cat=chart_cat,
                      chart_val=chart_val, chart_series=args.chart_series,
                      chart_height=args.chart_height)

    out_path = args.out or f"{args.name}.jrxml"
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(xml)

    print(f"OK: scaffolded {out_path} ({len(cols)} fields)")
    for cname, udt in cols:
        print(f"    {cname:<24} {udt:<14} -> {java_class(udt)}")


if __name__ == "__main__":
    main()
