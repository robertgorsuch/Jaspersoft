#!/usr/bin/env python3
"""Inject defaultValueExpression into the JR Library 'charts' sample parameters
so they render with data when run from the JRS UI (the samples otherwise rely on
the Java harness to supply MaxOrderID etc., and render blank without it).

Reads the charts sample jrxml, adds defaults to self-closing <parameter> tags
that lack one, and writes copies under output/charts_defaulted/charts/reports/
(a regenerable work dir) for deploy_jr_samples.ps1 to deploy.
"""
import os, re, glob

SRC = r"C:\Users\rgorsuch\jasperreports-7.0.6\demo\samples\charts\reports"
OUT = r"C:\Users\rgorsuch\tx-geocoder\output\charts_defaulted\charts\reports"
os.makedirs(OUT, exist_ok=True)

# literal default value expressions (Java) per parameter name
DEFAULTS = {
    "MaxOrderID": "11077",            # max OrderID in the demo data -> all orders
    "ChartFreightThreshold": "100.0",
    "Country": '"USA"',
}

def inject(text, name, expr):
    """Add a defaultValueExpression to parameter `name`, whether it is written
    self-closing (<parameter .../>) or with child elements
    (<parameter ...>...</parameter>). A parameter that already has a default is
    left untouched. Uses function replacements so `expr` (which may contain
    backslashes or digits) is never interpreted as a regex backreference."""
    default_xml = ('<defaultValueExpression><![CDATA['
                   + expr + ']]></defaultValueExpression>')

    sc = re.compile(r'<parameter name="' + re.escape(name) + r'"([^>]*?)/>')
    if sc.search(text):
        return sc.sub(lambda m: '<parameter name="' + name + '"' + m.group(1)
                      + '>' + default_xml + '</parameter>', text, count=1)

    full = re.compile(r'(<parameter name="' + re.escape(name)
                      + r'"[^>]*>)(.*?)(</parameter>)', re.DOTALL)

    def repl(m):
        if '<defaultValueExpression>' in m.group(2):
            return m.group(0)          # already has a default; leave it
        return m.group(1) + default_xml + m.group(2) + m.group(3)

    return full.sub(repl, text, count=1)

n = 0
for path in glob.glob(os.path.join(SRC, "*.jrxml")):
    base = os.path.splitext(os.path.basename(path))[0]
    text = open(path, encoding="utf-8").read()
    for name, expr in DEFAULTS.items():
        text = inject(text, name, expr)
    # ReportTitle default = the report's base name
    text = inject(text, "ReportTitle", '"' + base + '"')
    open(os.path.join(OUT, base + ".jrxml"), "w", encoding="utf-8").write(text)
    n += 1

print(f"wrote {n} defaulted chart jrxml to {OUT}")
