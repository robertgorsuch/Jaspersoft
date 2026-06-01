set TMPDIR=\gisdata\temp\
set UNZIPTOOL="C:\Program Files\7-Zip\7z.exe"
set WGETTOOL=C:\WINDOWS\system32\curl.exe
set PGBIN=C:\Program Files\PostgreSQL\14\bin\
set PGPORT=5432
set PGHOST=localhost
set PGUSER=postgres
if not defined PGPASSWORD set /p PGPASSWORD=PostgreSQL password for user postgres: 
set PGDATABASE=postgis_34_sample
set PSQL="%PGBIN%psql"
set SHP2PGSQL="%PGBIN%shp2pgsql"
set TXCC=001 003 005 007 009 011 013 015 017 019 021 023 025 027 029 031 033 035 037 039 041 043 045 047 049 051 053 055 057 059 061 063 065 067 069 071 073 075 077 079 081 083 085 087 089 091 093 095 097 099 101 103 105 107 109 111 113 115 117 119 121 123 125 127 129 131 133 135 137 139 141 143 145 147 149 151 153 155 157 159 161 163 165 167 169 171 173 175 177 179 181 183 185 187 189 191 193 195 197 199 201 203 205 207 209 211 213 215 217 219 221 223 225 227 229 231 233 235 237 239 241 243 245 247 249 251 253 255 257 259 261 263 265 267 269 271 273 275 277 279 281 283 285 287 289 291 293 295 297 299 301 303 305 307 309 311 313 315 317 319 321 323 325 327 329 331 333 335 337 339 341 343 345 347 349 351 353 355 357 359 361 363 365 367 369 371 373 375 377 379 381 383 385 387 389 391 393 395 397 399 401 403 405 407 409 411 413 415 417 419 421 423 425 427 429 431 433 435 437 439 441 443 445 447 449 451 453 455 457 459 461 463 465 467 469 471 473 475 477 479 481 483 485 487 489 491 493 495 497 499 501 503 505 507
cd \gisdata

cd \gisdata
call :getverified "www2.census.gov\geo\tiger\TIGER_RD18\LAYER\PLACE\tl_rd22_48_place.zip" "https://www2.census.gov/geo/tiger/TIGER_RD18/LAYER/PLACE/tl_rd22_48_place.zip"
cd \gisdata/www2.census.gov/geo/tiger/TIGER_RD18/LAYER/PLACE
del %TMPDIR%\*.* /Q
%PSQL% -c "DROP SCHEMA IF EXISTS tiger_staging CASCADE;"
%PSQL% -c "CREATE SCHEMA tiger_staging;"
%PSQL% -c "DO language 'plpgsql' $$ BEGIN IF NOT EXISTS (SELECT * FROM information_schema.schemata WHERE schema_name = 'tiger_data' ) THEN CREATE SCHEMA tiger_data; END IF;  END $$"
for /r %%z in (tl_rd22_48*_place.zip ) do %UNZIPTOOL% e %%z  -o%TMPDIR%
cd %TMPDIR%
%PSQL% -c "CREATE TABLE tiger_data.TX_place(CONSTRAINT pk_TX_place PRIMARY KEY (plcidfp) ) INHERITS(tiger.place);" 
%SHP2PGSQL% -D -c -s 4269 -g the_geom   -W "latin1" tl_rd22_48_place.dbf tiger_staging.tx_place | %PSQL%
%PSQL% -c "ALTER TABLE tiger_staging.TX_place RENAME geoid TO plcidfp;SELECT loader_load_staged_data(lower('TX_place'), lower('TX_place')); ALTER TABLE tiger_data.TX_place ADD CONSTRAINT uidx_TX_place_gid UNIQUE (gid);"
%PSQL% -c "CREATE INDEX idx_TX_place_soundex_name ON tiger_data.TX_place USING btree (soundex(name));"
%PSQL% -c "CREATE INDEX tiger_data_TX_place_the_geom_gist ON tiger_data.TX_place USING gist(the_geom);"
%PSQL% -c "ALTER TABLE tiger_data.TX_place ADD CONSTRAINT chk_statefp CHECK (statefp = '48');"
cd \gisdata
call :getverified "www2.census.gov\geo\tiger\TIGER_RD18\LAYER\COUSUB\tl_rd22_48_cousub.zip" "https://www2.census.gov/geo/tiger/TIGER_RD18/LAYER/COUSUB/tl_rd22_48_cousub.zip"
cd \gisdata/www2.census.gov/geo/tiger/TIGER_RD18/LAYER/COUSUB
del %TMPDIR%\*.* /Q
%PSQL% -c "DROP SCHEMA IF EXISTS tiger_staging CASCADE;"
%PSQL% -c "CREATE SCHEMA tiger_staging;"
%PSQL% -c "DO language 'plpgsql' $$ BEGIN IF NOT EXISTS (SELECT * FROM information_schema.schemata WHERE schema_name = 'tiger_data' ) THEN CREATE SCHEMA tiger_data; END IF;  END $$"
for /r %%z in (tl_rd22_48*_cousub.zip ) do %UNZIPTOOL% e %%z  -o%TMPDIR%
cd %TMPDIR%
%PSQL% -c "CREATE TABLE tiger_data.TX_cousub(CONSTRAINT pk_TX_cousub PRIMARY KEY (cosbidfp), CONSTRAINT uidx_TX_cousub_gid UNIQUE (gid)) INHERITS(tiger.cousub);" 
%SHP2PGSQL% -D -c -s 4269 -g the_geom   -W "latin1" tl_rd22_48_cousub.dbf tiger_staging.tx_cousub | %PSQL%
%PSQL% -c "ALTER TABLE tiger_staging.TX_cousub RENAME geoid TO cosbidfp;SELECT loader_load_staged_data(lower('TX_cousub'), lower('TX_cousub')); ALTER TABLE tiger_data.TX_cousub ADD CONSTRAINT chk_statefp CHECK (statefp = '48');"
%PSQL% -c "CREATE INDEX tiger_data_TX_cousub_the_geom_gist ON tiger_data.TX_cousub USING gist(the_geom);"
%PSQL% -c "CREATE INDEX idx_tiger_data_TX_cousub_countyfp ON tiger_data.TX_cousub USING btree(countyfp);"
cd \gisdata
call :getverified "www2.census.gov\geo\tiger\TIGER_RD18\LAYER\TRACT\tl_rd22_48_tract.zip" "https://www2.census.gov/geo/tiger/TIGER_RD18/LAYER/TRACT/tl_rd22_48_tract.zip"
cd \gisdata/www2.census.gov/geo/tiger/TIGER_RD18/LAYER/TRACT
del %TMPDIR%\*.* /Q
%PSQL% -c "DROP SCHEMA IF EXISTS tiger_staging CASCADE;"
%PSQL% -c "CREATE SCHEMA tiger_staging;"
%PSQL% -c "DO language 'plpgsql' $$ BEGIN IF NOT EXISTS (SELECT * FROM information_schema.schemata WHERE schema_name = 'tiger_data' ) THEN CREATE SCHEMA tiger_data; END IF;  END $$"
for /r %%z in (tl_rd22_48*_tract.zip ) do %UNZIPTOOL% e %%z  -o%TMPDIR%
cd %TMPDIR%
%PSQL% -c "CREATE TABLE tiger_data.TX_tract(CONSTRAINT pk_TX_tract PRIMARY KEY (tract_id) ) INHERITS(tiger.tract); " 
%SHP2PGSQL% -D -c -s 4269 -g the_geom   -W "latin1" tl_rd22_48_tract.dbf tiger_staging.tx_tract | %PSQL%
%PSQL% -c "ALTER TABLE tiger_staging.TX_tract RENAME geoid TO tract_id; SELECT loader_load_staged_data(lower('TX_tract'), lower('TX_tract')); "
	%PSQL% -c "CREATE INDEX tiger_data_TX_tract_the_geom_gist ON tiger_data.TX_tract USING gist(the_geom);"
	%PSQL% -c "VACUUM ANALYZE tiger_data.TX_tract;"
	%PSQL% -c "ALTER TABLE tiger_data.TX_tract ADD CONSTRAINT chk_statefp CHECK (statefp = '48');"
cd \gisdata
call :getverified "www2.census.gov\geo\tiger\TIGER_RD18\LAYER\TABBLOCK20\tl_rd22_48_tabblock20.zip" "https://www2.census.gov/geo/tiger/TIGER_RD18/LAYER/TABBLOCK20/tl_rd22_48_tabblock20.zip"
cd \gisdata/www2.census.gov/geo/tiger/TIGER_RD18/LAYER/TABBLOCK20
del %TMPDIR%\*.* /Q
%PSQL% -c "DROP SCHEMA IF EXISTS tiger_staging CASCADE;"
%PSQL% -c "CREATE SCHEMA tiger_staging;"
%PSQL% -c "DO language 'plpgsql' $$ BEGIN IF NOT EXISTS (SELECT * FROM information_schema.schemata WHERE schema_name = 'tiger_data' ) THEN CREATE SCHEMA tiger_data; END IF;  END $$"
for /r %%z in (tl_rd22_48*_tabblock20.zip ) do %UNZIPTOOL% e %%z  -o%TMPDIR%
cd %TMPDIR%
%PSQL% -c "CREATE TABLE tiger_data.TX_tabblock20(CONSTRAINT pk_TX_tabblock20 PRIMARY KEY (geoid)) INHERITS(tiger.tabblock20);" 
%SHP2PGSQL% -D -c -s 4269 -g the_geom   -W "latin1" tl_rd22_48_tabblock20.dbf tiger_staging.tx_tabblock20 | %PSQL%
%PSQL% -c "SELECT loader_load_staged_data(lower('TX_tabblock20'), lower('TX_tabblock20')); "
%PSQL% -c "ALTER TABLE tiger_data.TX_tabblock20 ADD CONSTRAINT chk_statefp CHECK (statefp = '48');"
%PSQL% -c "CREATE INDEX tiger_data_TX_tabblock20_the_geom_gist ON tiger_data.TX_tabblock20 USING gist(the_geom);"
%PSQL% -c "vacuum analyze tiger_data.TX_tabblock20;"
cd \gisdata
for %%c in (%TXCC%) do call :getverified "www2.census.gov\geo\tiger\TIGER_RD18\LAYER\FACES\tl_rd22_48%%c_faces.zip" "https://www2.census.gov/geo/tiger/TIGER_RD18/LAYER/FACES/tl_rd22_48%%c_faces.zip"
cd \gisdata/www2.census.gov/geo/tiger/TIGER_RD18/LAYER/FACES/
del %TMPDIR%\*.* /Q
%PSQL% -c "DROP SCHEMA IF EXISTS tiger_staging CASCADE;"
%PSQL% -c "CREATE SCHEMA tiger_staging;"
%PSQL% -c "DO language 'plpgsql' $$ BEGIN IF NOT EXISTS (SELECT * FROM information_schema.schemata WHERE schema_name = 'tiger_data' ) THEN CREATE SCHEMA tiger_data; END IF;  END $$"
for /r %%z in (tl_*_48*_faces*.zip ) do %UNZIPTOOL% e %%z  -o%TMPDIR%
cd %TMPDIR%
%PSQL% -c "CREATE TABLE tiger_data.TX_faces(CONSTRAINT pk_TX_faces PRIMARY KEY (gid)) INHERITS(tiger.faces);" 
for /r %%z in (*faces*.dbf) do (%SHP2PGSQL% -D   -D -s 4269 -g the_geom -W "latin1" %%z tiger_staging.TX_faces | %PSQL% & %PSQL% -c "SELECT loader_load_staged_data(lower('TX_faces'), lower('TX_faces'));")

%PSQL% -c "CREATE INDEX tiger_data_TX_faces_the_geom_gist ON tiger_data.TX_faces USING gist(the_geom);"
	%PSQL% -c "CREATE INDEX idx_tiger_data_TX_faces_tfid ON tiger_data.TX_faces USING btree (tfid);"
	%PSQL% -c "CREATE INDEX idx_tiger_data_TX_faces_countyfp ON tiger_data.TX_faces USING btree (countyfp);"
	%PSQL% -c "ALTER TABLE tiger_data.TX_faces ADD CONSTRAINT chk_statefp CHECK (statefp = '48');"
	%PSQL% -c "vacuum analyze tiger_data.TX_faces;"
cd \gisdata
for %%c in (%TXCC%) do call :getverified "www2.census.gov\geo\tiger\TIGER_RD18\LAYER\FEATNAMES\tl_rd22_48%%c_featnames.zip" "https://www2.census.gov/geo/tiger/TIGER_RD18/LAYER/FEATNAMES/tl_rd22_48%%c_featnames.zip"
cd \gisdata/www2.census.gov/geo/tiger/TIGER_RD18/LAYER/FEATNAMES/
del %TMPDIR%\*.* /Q
%PSQL% -c "DROP SCHEMA IF EXISTS tiger_staging CASCADE;"
%PSQL% -c "CREATE SCHEMA tiger_staging;"
%PSQL% -c "DO language 'plpgsql' $$ BEGIN IF NOT EXISTS (SELECT * FROM information_schema.schemata WHERE schema_name = 'tiger_data' ) THEN CREATE SCHEMA tiger_data; END IF;  END $$"
for /r %%z in (tl_*_48*_featnames*.zip ) do %UNZIPTOOL% e %%z  -o%TMPDIR%
cd %TMPDIR%
%PSQL% -c "CREATE TABLE tiger_data.TX_featnames(CONSTRAINT pk_TX_featnames PRIMARY KEY (gid)) INHERITS(tiger.featnames);ALTER TABLE tiger_data.TX_featnames ALTER COLUMN statefp SET DEFAULT '48';" 
for /r %%z in (*featnames*.dbf) do (%SHP2PGSQL% -D   -D -s 4269 -g the_geom -W "latin1" %%z tiger_staging.TX_featnames | %PSQL% & %PSQL% -c "SELECT loader_load_staged_data(lower('TX_featnames'), lower('TX_featnames'));")

%PSQL% -c "CREATE INDEX idx_tiger_data_TX_featnames_snd_name ON tiger_data.TX_featnames USING btree (soundex(name));"
%PSQL% -c "CREATE INDEX idx_tiger_data_TX_featnames_lname ON tiger_data.TX_featnames USING btree (lower(name));"
%PSQL% -c "CREATE INDEX idx_tiger_data_TX_featnames_tlid_statefp ON tiger_data.TX_featnames USING btree (tlid,statefp);"
%PSQL% -c "ALTER TABLE tiger_data.TX_featnames ADD CONSTRAINT chk_statefp CHECK (statefp = '48');"
%PSQL% -c "vacuum analyze tiger_data.TX_featnames;"
cd \gisdata
for %%c in (%TXCC%) do call :getverified "www2.census.gov\geo\tiger\TIGER_RD18\LAYER\EDGES\tl_rd22_48%%c_edges.zip" "https://www2.census.gov/geo/tiger/TIGER_RD18/LAYER/EDGES/tl_rd22_48%%c_edges.zip"
cd \gisdata/www2.census.gov/geo/tiger/TIGER_RD18/LAYER/EDGES/
del %TMPDIR%\*.* /Q
%PSQL% -c "DROP SCHEMA IF EXISTS tiger_staging CASCADE;"
%PSQL% -c "CREATE SCHEMA tiger_staging;"
%PSQL% -c "DO language 'plpgsql' $$ BEGIN IF NOT EXISTS (SELECT * FROM information_schema.schemata WHERE schema_name = 'tiger_data' ) THEN CREATE SCHEMA tiger_data; END IF;  END $$"
for /r %%z in (tl_*_48*_edges*.zip ) do %UNZIPTOOL% e %%z  -o%TMPDIR%
cd %TMPDIR%
%PSQL% -c "CREATE TABLE tiger_data.TX_edges(CONSTRAINT pk_TX_edges PRIMARY KEY (gid)) INHERITS(tiger.edges);"
for /r %%z in (*edges*.dbf) do (%SHP2PGSQL% -D   -D -s 4269 -g the_geom -W "latin1" %%z tiger_staging.TX_edges | %PSQL% & %PSQL% -c "SELECT loader_load_staged_data(lower('TX_edges'), lower('TX_edges'));")

%PSQL% -c "ALTER TABLE tiger_data.TX_edges ADD CONSTRAINT chk_statefp CHECK (statefp = '48');"
%PSQL% -c "CREATE INDEX idx_tiger_data_TX_edges_tlid ON tiger_data.TX_edges USING btree (tlid);"
%PSQL% -c "CREATE INDEX idx_tiger_data_TX_edgestfidr ON tiger_data.TX_edges USING btree (tfidr);"
%PSQL% -c "CREATE INDEX idx_tiger_data_TX_edges_tfidl ON tiger_data.TX_edges USING btree (tfidl);"
%PSQL% -c "CREATE INDEX idx_tiger_data_TX_edges_countyfp ON tiger_data.TX_edges USING btree (countyfp);"
%PSQL% -c "CREATE INDEX tiger_data_TX_edges_the_geom_gist ON tiger_data.TX_edges USING gist(the_geom);"
%PSQL% -c "CREATE INDEX idx_tiger_data_TX_edges_zipl ON tiger_data.TX_edges USING btree (zipl);"
%PSQL% -c "CREATE TABLE tiger_data.TX_zip_state_loc(CONSTRAINT pk_TX_zip_state_loc PRIMARY KEY(zip,stusps,place)) INHERITS(tiger.zip_state_loc);"
%PSQL% -c "INSERT INTO tiger_data.TX_zip_state_loc(zip,stusps,statefp,place) SELECT DISTINCT e.zipl, 'TX', '48', p.name FROM tiger_data.TX_edges AS e INNER JOIN tiger_data.TX_faces AS f ON (e.tfidl = f.tfid OR e.tfidr = f.tfid) INNER JOIN tiger_data.TX_place As p ON(f.statefp = p.statefp AND f.placefp = p.placefp ) WHERE e.zipl IS NOT NULL;"
%PSQL% -c "CREATE INDEX idx_tiger_data_TX_zip_state_loc_place ON tiger_data.TX_zip_state_loc USING btree(soundex(place));"
%PSQL% -c "ALTER TABLE tiger_data.TX_zip_state_loc ADD CONSTRAINT chk_statefp CHECK (statefp = '48');"
%PSQL% -c "vacuum analyze tiger_data.TX_edges;"
%PSQL% -c "vacuum analyze tiger_data.TX_zip_state_loc;"
%PSQL% -c "CREATE TABLE tiger_data.TX_zip_lookup_base(CONSTRAINT pk_TX_zip_state_loc_city PRIMARY KEY(zip,state, county, city, statefp)) INHERITS(tiger.zip_lookup_base);"
%PSQL% -c "INSERT INTO tiger_data.TX_zip_lookup_base(zip,state,county,city, statefp) SELECT DISTINCT e.zipl, 'TX', c.name,p.name,'48'  FROM tiger_data.TX_edges AS e INNER JOIN tiger.county As c  ON (e.countyfp = c.countyfp AND e.statefp = c.statefp AND e.statefp = '48') INNER JOIN tiger_data.TX_faces AS f ON (e.tfidl = f.tfid OR e.tfidr = f.tfid) INNER JOIN tiger_data.TX_place As p ON(f.statefp = p.statefp AND f.placefp = p.placefp ) WHERE e.zipl IS NOT NULL;"
%PSQL% -c "ALTER TABLE tiger_data.TX_zip_lookup_base ADD CONSTRAINT chk_statefp CHECK (statefp = '48');"
%PSQL% -c "CREATE INDEX idx_tiger_data_TX_zip_lookup_base_citysnd ON tiger_data.TX_zip_lookup_base USING btree(soundex(city));"
cd \gisdata
for %%c in (%TXCC%) do call :getverified "www2.census.gov\geo\tiger\TIGER_RD18\LAYER\ADDR\tl_rd22_48%%c_addr.zip" "https://www2.census.gov/geo/tiger/TIGER_RD18/LAYER/ADDR/tl_rd22_48%%c_addr.zip"
cd \gisdata/www2.census.gov/geo/tiger/TIGER_RD18/LAYER/ADDR/
del %TMPDIR%\*.* /Q
%PSQL% -c "DROP SCHEMA IF EXISTS tiger_staging CASCADE;"
%PSQL% -c "CREATE SCHEMA tiger_staging;"
%PSQL% -c "DO language 'plpgsql' $$ BEGIN IF NOT EXISTS (SELECT * FROM information_schema.schemata WHERE schema_name = 'tiger_data' ) THEN CREATE SCHEMA tiger_data; END IF;  END $$"
for /r %%z in (tl_*_48*_addr*.zip ) do %UNZIPTOOL% e %%z  -o%TMPDIR%
cd %TMPDIR%
%PSQL% -c "CREATE TABLE tiger_data.TX_addr(CONSTRAINT pk_TX_addr PRIMARY KEY (gid)) INHERITS(tiger.addr);ALTER TABLE tiger_data.TX_addr ALTER COLUMN statefp SET DEFAULT '48';" 
for /r %%z in (*addr*.dbf) do (%SHP2PGSQL% -D   -D -s 4269 -g the_geom -W "latin1" %%z tiger_staging.TX_addr | %PSQL% & %PSQL% -c "SELECT loader_load_staged_data(lower('TX_addr'), lower('TX_addr'));")

%PSQL% -c "ALTER TABLE tiger_data.TX_addr ADD CONSTRAINT chk_statefp CHECK (statefp = '48');"
	%PSQL% -c "CREATE INDEX idx_tiger_data_TX_addr_least_address ON tiger_data.TX_addr USING btree (least_hn(fromhn,tohn) );"
	%PSQL% -c "CREATE INDEX idx_tiger_data_TX_addr_tlid_statefp ON tiger_data.TX_addr USING btree (tlid, statefp);"
	%PSQL% -c "CREATE INDEX idx_tiger_data_TX_addr_zip ON tiger_data.TX_addr USING btree (zip);"
	%PSQL% -c "CREATE TABLE tiger_data.TX_zip_state(CONSTRAINT pk_TX_zip_state PRIMARY KEY(zip,stusps)) INHERITS(tiger.zip_state); "
	%PSQL% -c "INSERT INTO tiger_data.TX_zip_state(zip,stusps,statefp) SELECT DISTINCT zip, 'TX', '48' FROM tiger_data.TX_addr WHERE zip is not null;"
	%PSQL% -c "ALTER TABLE tiger_data.TX_zip_state ADD CONSTRAINT chk_statefp CHECK (statefp = '48');"
	%PSQL% -c "vacuum analyze tiger_data.TX_addr;"

goto :eof

REM ============================================================================
REM :getverified  "<relative output path>"  "<url>"
REM Downloads with curl, then validates the zip with `7z t` (CRC check).
REM Retries up to 5 times on corruption/failure; logs OK or GAVE UP.
REM This closes the silent-corruption gap: curl --fail catches HTTP errors but
REM NOT truncated/corrupt payloads (which is what silently broke PLACE/TRACT).
REM ============================================================================
:getverified
setlocal
set "OUT=%~1"
set "URL=%~2"
set "TRIES=0"
:gv_retry
set /a TRIES+=1
%WGETTOOL% --location --fail --retry 3 --create-dirs -o "%OUT%" "%URL%"
%UNZIPTOOL% t "%OUT%" >nul 2>&1
if errorlevel 1 (
  if %TRIES% LSS 5 (
    echo   [verify] CRC/download failed for "%OUT%" - retry %TRIES%/5
    del "%OUT%" >nul 2>&1
    goto :gv_retry
  )
  echo   [verify] GAVE UP after 5 tries: "%OUT%"
) else (
  echo   [verify] OK "%OUT%"
)
endlocal
goto :eof
