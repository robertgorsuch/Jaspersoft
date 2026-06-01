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
cd \gisdata

cd \gisdata
%WGETTOOL% --location --fail --retry 3 --create-dirs -o "www2.census.gov\geo\tiger\TIGER_RD18\LAYER\STATE\tl_rd22_us_state.zip" "https://www2.census.gov/geo/tiger/TIGER_RD18/LAYER/STATE/tl_rd22_us_state.zip"
cd \gisdata/www2.census.gov/geo/tiger/TIGER_RD18/LAYER/STATE
del %TMPDIR%\*.* /Q
%PSQL% -c "DROP SCHEMA IF EXISTS tiger_staging CASCADE;"
%PSQL% -c "CREATE SCHEMA tiger_staging;"
%PSQL% -c "DO language 'plpgsql' $$ BEGIN IF NOT EXISTS (SELECT * FROM information_schema.schemata WHERE schema_name = 'tiger_data' ) THEN CREATE SCHEMA tiger_data; END IF;  END $$"
for /r %%z in (tl_*state.zip ) do %UNZIPTOOL% e %%z  -o%TMPDIR%
cd %TMPDIR%
%PSQL% -c "CREATE TABLE tiger_data.state_all(CONSTRAINT pk_state_all PRIMARY KEY (statefp),CONSTRAINT uidx_state_all_stusps  UNIQUE (stusps), CONSTRAINT uidx_state_all_gid UNIQUE (gid) ) INHERITS(tiger.state); "
%SHP2PGSQL% -D -c -s 4269 -g the_geom   -W "latin1" tl_rd22_us_state.dbf tiger_staging.state | %PSQL%
%PSQL% -c "SELECT loader_load_staged_data(lower('state'), lower('state_all')); "
	%PSQL% -c "CREATE INDEX tiger_data_state_all_the_geom_gist ON tiger_data.state_all USING gist(the_geom);"
	%PSQL% -c "VACUUM ANALYZE tiger_data.state_all"
cd \gisdata
%WGETTOOL% --location --fail --retry 3 --create-dirs -o "www2.census.gov\geo\tiger\TIGER_RD18\LAYER\COUNTY\tl_rd22_us_county.zip" "https://www2.census.gov/geo/tiger/TIGER_RD18/LAYER/COUNTY/tl_rd22_us_county.zip"
cd \gisdata/www2.census.gov/geo/tiger/TIGER_RD18/LAYER/COUNTY
del %TMPDIR%\*.* /Q
%PSQL% -c "DROP SCHEMA IF EXISTS tiger_staging CASCADE;"
%PSQL% -c "CREATE SCHEMA tiger_staging;"
%PSQL% -c "DO language 'plpgsql' $$ BEGIN IF NOT EXISTS (SELECT * FROM information_schema.schemata WHERE schema_name = 'tiger_data' ) THEN CREATE SCHEMA tiger_data; END IF;  END $$"
for /r %%z in (tl_*county.zip ) do %UNZIPTOOL% e %%z  -o%TMPDIR%
cd %TMPDIR%
%PSQL% -c "CREATE TABLE tiger_data.county_all(CONSTRAINT pk_tiger_data_county_all PRIMARY KEY (cntyidfp),CONSTRAINT uidx_tiger_data_county_all_gid UNIQUE (gid)  ) INHERITS(tiger.county); " 
%SHP2PGSQL% -D -c -s 4269 -g the_geom   -W "latin1" tl_rd22_us_county.dbf tiger_staging.county | %PSQL%
%PSQL% -c "ALTER TABLE tiger_staging.county RENAME geoid TO cntyidfp;  SELECT loader_load_staged_data(lower('county'), lower('county_all'));"
	%PSQL% -c "CREATE INDEX tiger_data_county_the_geom_gist ON tiger_data.county_all USING gist(the_geom);"
	%PSQL% -c "CREATE UNIQUE INDEX uidx_tiger_data_county_all_statefp_countyfp ON tiger_data.county_all USING btree(statefp,countyfp);"
	%PSQL% -c "CREATE TABLE tiger_data.county_all_lookup ( CONSTRAINT pk_county_all_lookup PRIMARY KEY (st_code, co_code)) INHERITS (tiger.county_lookup);"
	%PSQL% -c "VACUUM ANALYZE tiger_data.county_all;"
	%PSQL% -c "INSERT INTO tiger_data.county_all_lookup(st_code, state, co_code, name) SELECT CAST(s.statefp as integer), s.abbrev, CAST(c.countyfp as integer), c.name FROM tiger_data.county_all As c INNER JOIN state_lookup As s ON s.statefp = c.statefp;"
	%PSQL% -c "VACUUM ANALYZE tiger_data.county_all_lookup;" 
