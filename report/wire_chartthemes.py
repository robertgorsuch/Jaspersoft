#!/usr/bin/env python3
"""Wire the chartthemes AllChartsReport to CSV data adapters on JRS.

Builds 5 CSV data adapters (datasource mode, first row = header, CRLF) pointing
at the uploaded repo CSVs, and rewrites the report so each subdataset uses its
adapter via a net.sf.jasperreports.data.adapter property (removing the
$P{...JRCsvDataSource} dataSourceExpressions the Java harness used to supply).
"""
import os, re

SRC = r"C:\Users\rgorsuch\jasperreports-7.0.6\demo\samples\chartthemes\reports\AllChartsReport.jrxml"
OUTDIR = r"C:\Users\rgorsuch\tx-geocoder\output\chartthemes_wired"
os.makedirs(OUTDIR, exist_ok=True)

# subDataset name -> (adapter resource name, csv resource name)
DATASETS = {
    "categoryDataset":   ("ct_category_adapter",   "ct_category"),
    "pieDataset":        ("ct_pie_adapter",        "ct_pie"),
    "xyDataset":         ("ct_xy_adapter",         "ct_xy"),
    "timeSeriesDataset": ("ct_timeseries_adapter", "ct_timeseries"),
    "timePeriodDataset": ("ct_timeperiod_adapter", "ct_timeperiod"),
}
REPO = "repo:/reports/jr_samples/data/"

ADAPTER_TMPL = """<?xml version="1.0" encoding="UTF-8"?>
<csvDataAdapter class="net.sf.jasperreports.data.csv.CsvDataAdapterImpl">
\t<name>{name}</name>
\t<fileName>{repo}{csv}</fileName>
\t<useFirstRowAsHeader>true</useFirstRowAsHeader>
\t<recordDelimiter>&#13;&#10;</recordDelimiter>
\t<fieldDelimiter>,</fieldDelimiter>
\t<queryExecuterMode>false</queryExecuterMode>
\t<datePattern>yyyy-MM-dd HH:mm:ss</datePattern>
</csvDataAdapter>
"""

# 1. write adapter files
for ds, (adapter, csv) in DATASETS.items():
    with open(os.path.join(OUTDIR, adapter + ".jrdax"), "w", encoding="utf-8") as f:
        f.write(ADAPTER_TMPL.format(name=adapter, repo=REPO, csv=csv))

# 2. transform the report
text = open(SRC, encoding="utf-8").read()

# insert a data.adapter property right after each <dataset name="X" ...>
for ds, (adapter, csv) in DATASETS.items():
    pat = re.compile(r'(<dataset name="' + re.escape(ds) + r'"[^>]*>)')
    prop = (r'\1\n\t\t<property name="net.sf.jasperreports.data.adapter" value="'
            + REPO + adapter + '"/>')
    text, n = pat.subn(prop, text)
    assert n == 1, f"{ds}: expected 1 match, got {n}"

# remove the $P{...} dataSourceExpressions so datasetRuns fall back to the adapter
text, removed = re.subn(
    r'\s*<dataSourceExpression><!\[CDATA\[\$P\{[A-Za-z0-9_]+\}\]\]></dataSourceExpression>',
    "", text)

open(os.path.join(OUTDIR, "AllChartsReport.jrxml"), "w", encoding="utf-8").write(text)
print(f"wrote 5 adapters + AllChartsReport.jrxml (removed {removed} dataSourceExpressions)")
