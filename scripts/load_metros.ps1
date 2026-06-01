# Verified loader for major TX metro counties (geocode layers: faces, featnames, edges, addr)
# Downloads each zip, validates with `7z t`, retries up to 5x, then appends into existing tiger_data.TX_* tables.
$ErrorActionPreference = "Continue"
$curl = "C:\WINDOWS\system32\curl.exe"
$z7   = "C:\Program Files\7-Zip\7z.exe"
$PSQL = "C:\Program Files\PostgreSQL\14\bin\psql.exe"
$SHP2 = "C:\Program Files\PostgreSQL\14\bin\shp2pgsql.exe"
$env:PGHOST="localhost"; $env:PGPORT="5432"; $env:PGUSER="postgres"
if(-not $env:PGPASSWORD){throw "Set `$env:PGPASSWORD before running"}; $env:PGDATABASE="postgis_34_sample"; $env:PGCLIENTENCODING="UTF8"
$base = "https://www2.census.gov/geo/tiger/TIGER_RD18/LAYER"
$tmp  = "C:\gisdata\geocode\_load_tmp"
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

$counties = @(
 @{c="201";n="Harris (Houston)"}, @{c="113";n="Dallas"}, @{c="439";n="Tarrant (Ft Worth)"},
 @{c="029";n="Bexar (San Antonio)"}, @{c="085";n="Collin"}, @{c="121";n="Denton"},
 @{c="141";n="El Paso"}, @{c="215";n="Hidalgo"}, @{c="157";n="Fort Bend"},
 @{c="491";n="Williamson"}, @{c="339";n="Montgomery"}, @{c="061";n="Cameron"},
 @{c="355";n="Nueces"}, @{c="027";n="Bell"}, @{c="167";n="Galveston"}, @{c="039";n="Brazoria"}
)
$layers = @("faces","featnames","edges","addr")  # PLACE already loaded statewide

& $PSQL -c "CREATE SCHEMA IF NOT EXISTS tiger_staging;" | Out-Null

function Get-Verified($url, $out) {
  for ($i=1; $i -le 5; $i++) {
    & $curl --location --fail --retry 3 --create-dirs -s -S -o $out $url 2>&1 | Out-Null
    if (Test-Path $out) { & $z7 t $out > $null 2>&1; if ($LASTEXITCODE -eq 0) { return $true } }
    Start-Sleep 2
  }
  return $false
}

$ci = 0
foreach ($co in $counties) {
  $ci++
  $fips = "48$($co.c)"
  Write-Output "===== [$ci/16] $($co.n)  $fips  $(Get-Date -Format HH:mm:ss) ====="
  foreach ($layer in $layers) {
    $url = "$base/$($layer.ToUpper())/tl_rd22_${fips}_$layer.zip"
    $zip = "$tmp\tl_rd22_${fips}_$layer.zip"
    Get-ChildItem $tmp -File | Remove-Item -Force -ErrorAction SilentlyContinue
    if (-not (Get-Verified $url $zip)) { Write-Output "  $layer : DOWNLOAD FAILED (skipped)"; continue }
    & $z7 e $zip "-o$tmp" -y > $null 2>&1
    $dbf = Get-ChildItem "$tmp\*.dbf" | Select-Object -First 1
    if (-not $dbf) { Write-Output "  $layer : no dbf after extract (skipped)"; continue }
    # drop+create staging for just this county, then append into tiger_data.TX_<layer>
    cmd /c "`"$SHP2`" -d -s 4269 -g the_geom -W latin1 `"$($dbf.FullName)`" tiger_staging.tx_$layer | `"$PSQL`"" > $null 2>&1
    & $PSQL -t -c "SELECT loader_load_staged_data(lower('tx_$layer'), lower('tx_$layer'));" 2>&1 | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object { Write-Output "  $layer : appended $_ rows" }
  }
}

Write-Output "===== Rebuilding ZIP lookup tables from all loaded data $(Get-Date -Format HH:mm:ss) ====="
& $PSQL -c "TRUNCATE tiger_data.TX_zip_state, tiger_data.TX_zip_state_loc, tiger_data.TX_zip_lookup_base;" 2>&1 | Out-Null
& $PSQL -c "INSERT INTO tiger_data.TX_zip_state(zip,stusps,statefp) SELECT DISTINCT zip,'TX','48' FROM tiger_data.TX_addr WHERE zip IS NOT NULL ON CONFLICT DO NOTHING;" 2>&1 | ForEach-Object { Write-Output $_ }
& $PSQL -c "INSERT INTO tiger_data.TX_zip_state_loc(zip,stusps,statefp,place) SELECT DISTINCT e.zipl,'TX','48',p.name FROM tiger_data.TX_edges e JOIN tiger_data.TX_faces f ON (e.tfidl=f.tfid OR e.tfidr=f.tfid) JOIN tiger_data.TX_place p ON (f.statefp=p.statefp AND f.placefp=p.placefp) WHERE e.zipl IS NOT NULL ON CONFLICT DO NOTHING;" 2>&1 | ForEach-Object { Write-Output $_ }
& $PSQL -c "INSERT INTO tiger_data.TX_zip_lookup_base(zip,state,county,city,statefp) SELECT DISTINCT e.zipl,'TX',c.name,p.name,'48' FROM tiger_data.TX_edges e JOIN tiger.county c ON (e.countyfp=c.countyfp AND e.statefp=c.statefp AND e.statefp='48') JOIN tiger_data.TX_faces f ON (e.tfidl=f.tfid OR e.tfidr=f.tfid) JOIN tiger_data.TX_place p ON (f.statefp=p.statefp AND f.placefp=p.placefp) WHERE e.zipl IS NOT NULL ON CONFLICT DO NOTHING;" 2>&1 | ForEach-Object { Write-Output $_ }
& $PSQL -c "VACUUM ANALYZE tiger_data.TX_edges; VACUUM ANALYZE tiger_data.TX_faces; VACUUM ANALYZE tiger_data.TX_featnames; VACUUM ANALYZE tiger_data.TX_addr;" 2>&1 | Out-Null
Write-Output "===== METRO LOAD COMPLETE $(Get-Date -Format HH:mm:ss) ====="
