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
        r"\copy (SELECT column_name, udt_name FROM information_schema.columns "
        "WHERE table_name = '_jr_scaffold' ORDER BY ordinal_position) "
        "TO STDOUT WITH (FORMAT csv)\n"
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
    """Weighted column widths summing exactly to `total`."""
    weights = []
    for _name, udt in cols:
        jc = java_class(udt)
        weights.append(1.0 if (is_right_aligned(jc)) else 1.6)
    s = sum(weights)
    raw = [max(40, int(total * w / s)) for w in weights]
    # fix rounding so widths sum to exactly total
    diff = total - sum(raw)
    raw[-1] += diff
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


def build_jrxml(name, title, subtitle, query, cols, *, page_w, page_h,
                margin=20):
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

    title = args.title or label_for(args.name)
    xml = build_jrxml(args.name, title, args.subtitle, query, cols,
                      page_w=w, page_h=h)

    out_path = args.out or f"{args.name}.jrxml"
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(xml)

    print(f"OK: scaffolded {out_path} ({len(cols)} fields)")
    for cname, udt in cols:
        print(f"    {cname:<24} {udt:<14} -> {java_class(udt)}")


if __name__ == "__main__":
    main()
