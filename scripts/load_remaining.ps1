# Verified loader for ALL remaining TX counties (geocode layers: faces, featnames, edges, addr).
# Idempotent: queries the DB for already-loaded counties and skips them, so it can be re-run after an interruption.
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
$layers = @("faces","featnames","edges","addr")

& $PSQL -c "CREATE SCHEMA IF NOT EXISTS tiger_staging;" 2>$null | Out-Null

# all 254 TX county codes (odd 001..507) minus those already in tx_edges
$all = 1..507 | Where-Object { $_ % 2 -eq 1 } | ForEach-Object { '{0:000}' -f $_ }
$loaded = (& $PSQL -A -t -c "SELECT string_agg(DISTINCT countyfp, ',') FROM tiger_data.tx_edges;" 2>$null).Trim().Split(',')
$remaining = $all | Where-Object { $loaded -notcontains $_ }
Write-Output "Already loaded: $($loaded.Count) counties. Remaining to load: $($remaining.Count)."

function Get-Verified($url, $out) {
  for ($i=1; $i -le 6; $i++) {
    & $curl --location --fail --retry 3 --create-dirs -s -S -o $out $url 2>$null | Out-Null
    if (Test-Path $out) { & $z7 t $out > $null 2>&1; if ($LASTEXITCODE -eq 0) { return $true } }
    Start-Sleep 2
  }
  return $false
}

$ci = 0; $tot = $remaining.Count
foreach ($cc in $remaining) {
  $ci++
  $fips = "48$cc"
  Write-Output "===== [$ci/$tot] county $fips  $(Get-Date -Format 'MM-dd HH:mm:ss') ====="
  foreach ($layer in $layers) {
    $url = "$base/$($layer.ToUpper())/tl_rd22_${fips}_$layer.zip"
    $zip = "$tmp\tl_rd22_${fips}_$layer.zip"
    Get-ChildItem $tmp -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    if (-not (Get-Verified $url $zip)) { Write-Output "  $layer : DOWNLOAD FAILED (skipped)"; continue }
    & $z7 e $zip "-o$tmp" -y > $null 2>&1
    $dbf = Get-ChildItem "$tmp\*.dbf" | Select-Object -First 1
    if (-not $dbf) { Write-Output "  $layer : no dbf (skipped)"; continue }
    cmd /c "`"$SHP2`" -d -s 4269 -g the_geom -W latin1 `"$($dbf.FullName)`" tiger_staging.tx_$layer | `"$PSQL`"" > $null 2>&1
    $r = (& $PSQL -A -t -c "SELECT loader_load_staged_data(lower('tx_$layer'), lower('tx_$layer'));" 2>$null)
    Write-Output "  $layer : appended $r rows"
  }
}

Write-Output "===== Rebuilding ZIP lookup tables (full state) $(Get-Date -Format 'MM-dd HH:mm:ss') ====="
& $PSQL -c "TRUNCATE tiger_data.TX_zip_state, tiger_data.TX_zip_state_loc, tiger_data.TX_zip_lookup_base;" 2>$null | Out-Null
& $PSQL -c "INSERT INTO tiger_data.TX_zip_state(zip,stusps,statefp) SELECT DISTINCT zip,'TX','48' FROM tiger_data.TX_addr WHERE zip IS NOT NULL ON CONFLICT DO NOTHING;" 2>$null | Out-Null
& $PSQL -c "INSERT INTO tiger_data.TX_zip_state_loc(zip,stusps,statefp,place) SELECT DISTINCT e.zipl,'TX','48',p.name FROM tiger_data.TX_edges e JOIN tiger_data.TX_faces f ON (e.tfidl=f.tfid OR e.tfidr=f.tfid) JOIN tiger_data.TX_place p ON (f.statefp=p.statefp AND f.placefp=p.placefp) WHERE e.zipl IS NOT NULL ON CONFLICT DO NOTHING;" 2>$null | Out-Null
& $PSQL -c "INSERT INTO tiger_data.TX_zip_lookup_base(zip,state,county,city,statefp) SELECT DISTINCT e.zipl,'TX',c.name,p.name,'48' FROM tiger_data.TX_edges e JOIN tiger.county c ON (e.countyfp=c.countyfp AND e.statefp=c.statefp AND e.statefp='48') JOIN tiger_data.TX_faces f ON (e.tfidl=f.tfid OR e.tfidr=f.tfid) JOIN tiger_data.TX_place p ON (f.statefp=p.statefp AND f.placefp=p.placefp) WHERE e.zipl IS NOT NULL ON CONFLICT DO NOTHING;" 2>$null | Out-Null
& $PSQL -c "VACUUM ANALYZE tiger_data.TX_edges; VACUUM ANALYZE tiger_data.TX_faces; VACUUM ANALYZE tiger_data.TX_featnames; VACUUM ANALYZE tiger_data.TX_addr;" 2>$null | Out-Null
Write-Output "===== REMAINING-COUNTY LOAD COMPLETE $(Get-Date -Format 'MM-dd HH:mm:ss') ====="
