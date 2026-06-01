@echo off
REM Loads geocoder layers: PLACE (statewide) + EDGES/FEATNAMES/ADDR for Travis County (48453)
set PGBIN=C:\Program Files\PostgreSQL\14\bin\
set PGPORT=5432
set PGHOST=localhost
set PGUSER=postgres
if not defined PGPASSWORD set /p PGPASSWORD=PostgreSQL password for user postgres: 
set PGDATABASE=postgis_34_sample
set PSQL="%PGBIN%psql"
set SHP2PGSQL="%PGBIN%shp2pgsql"
set G=C:\gisdata\geocode

echo === PLACE (statewide) ===
%PSQL% -c "DROP SCHEMA IF EXISTS tiger_staging CASCADE;"
%PSQL% -c "CREATE SCHEMA tiger_staging;"
%PSQL% -c "CREATE TABLE tiger_data.TX_place(CONSTRAINT pk_TX_place PRIMARY KEY (plcidfp) ) INHERITS(tiger.place);"
%SHP2PGSQL% -D -c -s 4269 -g the_geom -W "latin1" %G%\place\tl_rd22_48_place.dbf tiger_staging.tx_place | %PSQL%
%PSQL% -c "ALTER TABLE tiger_staging.TX_place RENAME geoid TO plcidfp;SELECT loader_load_staged_data(lower('TX_place'), lower('TX_place')); ALTER TABLE tiger_data.TX_place ADD CONSTRAINT uidx_TX_place_gid UNIQUE (gid);"
%PSQL% -c "CREATE INDEX idx_TX_place_soundex_name ON tiger_data.TX_place USING btree (soundex(name));"
%PSQL% -c "CREATE INDEX tiger_data_TX_place_the_geom_gist ON tiger_data.TX_place USING gist(the_geom);"
%PSQL% -c "ALTER TABLE tiger_data.TX_place ADD CONSTRAINT chk_statefp CHECK (statefp = '48');"

echo === EDGES (Travis 48453) ===
%PSQL% -c "DROP SCHEMA IF EXISTS tiger_staging CASCADE;"
%PSQL% -c "CREATE SCHEMA tiger_staging;"
%PSQL% -c "CREATE TABLE tiger_data.TX_edges(CONSTRAINT pk_TX_edges PRIMARY KEY (gid)) INHERITS(tiger.edges);"
%SHP2PGSQL% -D -s 4269 -g the_geom -W "latin1" %G%\edges\tl_rd22_48453_edges.dbf tiger_staging.TX_edges | %PSQL%
%PSQL% -c "SELECT loader_load_staged_data(lower('TX_edges'), lower('TX_edges'));"
%PSQL% -c "ALTER TABLE tiger_data.TX_edges ADD CONSTRAINT chk_statefp CHECK (statefp = '48');"
%PSQL% -c "CREATE INDEX idx_tiger_data_TX_edges_tlid ON tiger_data.TX_edges USING btree (tlid);"
%PSQL% -c "CREATE INDEX idx_tiger_data_TX_edges_countyfp ON tiger_data.TX_edges USING btree (countyfp);"
%PSQL% -c "CREATE INDEX tiger_data_TX_edges_the_geom_gist ON tiger_data.TX_edges USING gist(the_geom);"
%PSQL% -c "CREATE INDEX idx_tiger_data_TX_edges_zipl ON tiger_data.TX_edges USING btree (zipl);"
%PSQL% -c "vacuum analyze tiger_data.TX_edges;"

echo === FEATNAMES (Travis 48453) ===
%PSQL% -c "DROP SCHEMA IF EXISTS tiger_staging CASCADE;"
%PSQL% -c "CREATE SCHEMA tiger_staging;"
%PSQL% -c "CREATE TABLE tiger_data.TX_featnames(CONSTRAINT pk_TX_featnames PRIMARY KEY (gid)) INHERITS(tiger.featnames);ALTER TABLE tiger_data.TX_featnames ALTER COLUMN statefp SET DEFAULT '48';"
%SHP2PGSQL% -D -s 4269 -g the_geom -W "latin1" %G%\featnames\tl_rd22_48453_featnames.dbf tiger_staging.TX_featnames | %PSQL%
%PSQL% -c "SELECT loader_load_staged_data(lower('TX_featnames'), lower('TX_featnames'));"
%PSQL% -c "CREATE INDEX idx_tiger_data_TX_featnames_snd_name ON tiger_data.TX_featnames USING btree (soundex(name));"
%PSQL% -c "CREATE INDEX idx_tiger_data_TX_featnames_lname ON tiger_data.TX_featnames USING btree (lower(name));"
%PSQL% -c "CREATE INDEX idx_tiger_data_TX_featnames_tlid_statefp ON tiger_data.TX_featnames USING btree (tlid,statefp);"
%PSQL% -c "ALTER TABLE tiger_data.TX_featnames ADD CONSTRAINT chk_statefp CHECK (statefp = '48');"
%PSQL% -c "vacuum analyze tiger_data.TX_featnames;"

echo === ADDR (Travis 48453) ===
%PSQL% -c "DROP SCHEMA IF EXISTS tiger_staging CASCADE;"
%PSQL% -c "CREATE SCHEMA tiger_staging;"
%PSQL% -c "CREATE TABLE tiger_data.TX_addr(CONSTRAINT pk_TX_addr PRIMARY KEY (gid)) INHERITS(tiger.addr);ALTER TABLE tiger_data.TX_addr ALTER COLUMN statefp SET DEFAULT '48';"
%SHP2PGSQL% -D -s 4269 -g the_geom -W "latin1" %G%\addr\tl_rd22_48453_addr.dbf tiger_staging.TX_addr | %PSQL%
%PSQL% -c "SELECT loader_load_staged_data(lower('TX_addr'), lower('TX_addr'));"
%PSQL% -c "CREATE INDEX idx_tiger_data_TX_addr_least_address ON tiger_data.TX_addr USING btree (least_hn(fromhn,tohn) );"
%PSQL% -c "CREATE INDEX idx_tiger_data_TX_addr_tlid_statefp ON tiger_data.TX_addr USING btree (tlid, statefp);"
%PSQL% -c "CREATE INDEX idx_tiger_data_TX_addr_zip ON tiger_data.TX_addr USING btree (zip);"
%PSQL% -c "vacuum analyze tiger_data.TX_addr;"

echo === DONE ===
