# JasperReports 7 jrxml cheat-sheet (JR7-native, NOT 6.x)

JR 7.0.6 introduced a new Jackson-based jrxml schema that is **not backward
compatible** with 6.x. A 6.x jrxml will fail the JR7 loader. There is no
standalone CLI converter — to migrate a 6.x file, open it in Jaspersoft Studio
(it auto-upgrades on save). The scaffolder in this skill emits JR7-native XML
directly.

## What changed from 6.x
- **No XML namespace / DOCTYPE.** Root element is `<jasperReport name="..">`.
- `<queryString>` → `<query language="SQL">`.
- `<reportElement>` is **gone**. `x`, `y`, `width`, `height` are flattened
  directly onto the element.
- Generic element tag is `<element kind="...">` instead of `<textField>`,
  `<staticText>`, etc. being top-level tags.
- Style attributes (`fontSize`, `bold`, `forecolor`, `hTextAlign`, …) live as
  attributes on `<element>`.

## Root
```xml
<jasperReport name="my_report" language="java"
    pageWidth="595" pageHeight="842" columnWidth="555"
    leftMargin="20" rightMargin="20" topMargin="20" bottomMargin="20">
```
A4 portrait = 595×842, columnWidth = pageWidth − left − right. Letter = 612×792.

## Query + fields
```xml
<query language="SQL"><![CDATA[ SELECT ... ]]></query>
<field name="county" class="java.lang.String"/>
<field name="population" class="java.lang.Long"/>
```

## Bands
- **Single-instance bands** put `height` on the section tag itself:
  `<title height="44"> … </title>`, `<columnHeader height="18"> … </columnHeader>`,
  `<pageFooter height="16"> … </pageFooter>`, `<summary height="46"> … </summary>`.
- **Repeating / multi-band sections** wrap a `<band>`:
  `<detail><band height="13"> … </band></detail>`, and group headers/footers
  `<groupHeader><band height="24"> … </band></groupHeader>`.

## Elements
```xml
<!-- static label -->
<element kind="staticText" x="6" y="0" width="194" height="18"
    fontSize="9.0" bold="true" forecolor="#FFFFFF" vTextAlign="Middle">
  <text><![CDATA[County]]></text>
</element>

<!-- data-bound field -->
<element kind="textField" x="300" y="0" width="80" height="13"
    fontSize="8.0" hTextAlign="Right" vTextAlign="Middle" pattern="#,##0">
  <expression><![CDATA[$F{population}]]></expression>
</element>

<!-- shapes -->
<element kind="rectangle" x="0" y="0" width="555" height="18"
    mode="Opaque" backcolor="#34495E" forecolor="#34495E"/>
<element kind="line" x="0" y="12" width="555" height="1" forecolor="#EEEEEE"/>
```
- `kind` ∈ `textField | staticText | line | rectangle | image | …`
- `textField` uses `<expression>`; `staticText` uses `<text>`.
- Alignment: `hTextAlign="Left|Center|Right"`, `vTextAlign="Top|Middle|Bottom"`.
- `pattern` is a `java.text`/`DecimalFormat` pattern (`#,##0`, `#,##0.00`,
  `yyyy-MM-dd`).

## Variables and groups
```xml
<variable name="totPop" class="java.lang.Long" calculation="Sum">
  <expression><![CDATA[$F{population}]]></expression>
</variable>

<group name="DensityClass">
  <expression><![CDATA[$F{density_class}]]></expression>
  <groupHeader><band height="24"> … </band></groupHeader>
  <groupFooter><band height="6"> … </band></groupFooter>
</group>
```

## Built-ins
- `$V{PAGE_NUMBER}` — page counter. For "Page X of Y", the total-pages field
  needs `evaluationTime="Report"`.
- `$F{name}` fields, `$P{name}` parameters, `$V{name}` variables.

## Gotchas
- PDF export lives in the `jasperreports-pdf` (OpenPDF) module, **not** core.
- Field `class` must match the JDBC type (see PG→Java map in scaffold_jrxml.py):
  int4→Integer, int8→Long, numeric→BigDecimal, float8→Double, bool→Boolean,
  date→java.sql.Date, timestamp(tz)→java.sql.Timestamp, else String.
- Ground-truth reference file:
  `../../../report/tx_density_blockgroup_report_jr7.jrxml`.
