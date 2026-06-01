@echo off
set PGBIN=C:\Program Files\PostgreSQL\14\bin\
set PGPORT=5432
set PGHOST=localhost
set PGUSER=postgres
if not defined PGPASSWORD set /p PGPASSWORD=PostgreSQL password for user postgres: 
set PGDATABASE=postgis_34_sample
set PSQL="%PGBIN%psql"
set SHP2PGSQL="%PGBIN%shp2pgsql"
set G=C:\gisdata\geocode

echo === FACES (Travis 48453) ===
%PSQL% -c "DROP SCHEMA IF EXISTS tiger_staging CASCADE;"
%PSQL% -c "CREATE SCHEMA tiger_staging;"
%PSQL% -c "DROP TABLE IF EXISTS tiger_data.TX_faces CASCADE;"
%PSQL% -c "CREATE TABLE tiger_data.TX_faces(CONSTRAINT pk_TX_faces PRIMARY KEY (gid)) INHERITS(tiger.faces);"
%SHP2PGSQL% -D -s 4269 -g the_geom -W "latin1" %G%\faces\tl_rd22_48453_faces.dbf tiger_staging.TX_faces | %PSQL%
%PSQL% -c "SELECT loader_load_staged_data(lower('TX_faces'), lower('TX_faces'));"
%PSQL% -c "CREATE INDEX tiger_data_TX_faces_the_geom_gist ON tiger_data.TX_faces USING gist(the_geom);"
%PSQL% -c "CREATE INDEX idx_tiger_data_TX_faces_tfid ON tiger_data.TX_faces USING btree (tfid);"
%PSQL% -c "CREATE INDEX idx_tiger_data_TX_faces_countyfp ON tiger_data.TX_faces USING btree (countyfp);"
%PSQL% -c "ALTER TABLE tiger_data.TX_faces ADD CONSTRAINT chk_statefp CHECK (statefp = '48');"
%PSQL% -c "vacuum analyze tiger_data.TX_faces;"

echo === TX_zip_state (from ADDR) ===
%PSQL% -c "DROP TABLE IF EXISTS tiger_data.TX_zip_state CASCADE; CREATE TABLE tiger_data.TX_zip_state(CONSTRAINT pk_TX_zip_state PRIMARY KEY(zip,stusps)) INHERITS(tiger.zip_state);"
%PSQL% -c "INSERT INTO tiger_data.TX_zip_state(zip,stusps,statefp) SELECT DISTINCT zip, 'TX', '48' FROM tiger_data.TX_addr WHERE zip is not null;"
%PSQL% -c "ALTER TABLE tiger_data.TX_zip_state ADD CONSTRAINT chk_statefp CHECK (statefp = '48');"

echo === TX_zip_state_loc (edges+faces+place) ===
%PSQL% -c "DROP TABLE IF EXISTS tiger_data.TX_zip_state_loc CASCADE; CREATE TABLE tiger_data.TX_zip_state_loc(CONSTRAINT pk_TX_zip_state_loc PRIMARY KEY(zip,stusps,place)) INHERITS(tiger.zip_state_loc);"
%PSQL% -c "INSERT INTO tiger_data.TX_zip_state_loc(zip,stusps,statefp,place) SELECT DISTINCT e.zipl, 'TX', '48', p.name FROM tiger_data.TX_edges AS e INNER JOIN tiger_data.TX_faces AS f ON (e.tfidl = f.tfid OR e.tfidr = f.tfid) INNER JOIN tiger_data.TX_place As p ON(f.statefp = p.statefp AND f.placefp = p.placefp ) WHERE e.zipl IS NOT NULL;"
%PSQL% -c "CREATE INDEX idx_tiger_data_TX_zip_state_loc_place ON tiger_data.TX_zip_state_loc USING btree(soundex(place));"
%PSQL% -c "ALTER TABLE tiger_data.TX_zip_state_loc ADD CONSTRAINT chk_statefp CHECK (statefp = '48');"

echo === TX_zip_lookup_base (edges+county+faces+place) ===
%PSQL% -c "DROP TABLE IF EXISTS tiger_data.TX_zip_lookup_base CASCADE; CREATE TABLE tiger_data.TX_zip_lookup_base(CONSTRAINT pk_TX_zip_state_loc_city PRIMARY KEY(zip,state, county, city, statefp)) INHERITS(tiger.zip_lookup_base);"
%PSQL% -c "INSERT INTO tiger_data.TX_zip_lookup_base(zip,state,county,city, statefp) SELECT DISTINCT e.zipl, 'TX', c.name,p.name,'48' FROM tiger_data.TX_edges AS e INNER JOIN tiger.county As c ON (e.countyfp = c.countyfp AND e.statefp = c.statefp AND e.statefp = '48') INNER JOIN tiger_data.TX_faces AS f ON (e.tfidl = f.tfid OR e.tfidr = f.tfid) INNER JOIN tiger_data.TX_place As p ON(f.statefp = p.statefp AND f.placefp = p.placefp ) WHERE e.zipl IS NOT NULL;"
%PSQL% -c "ALTER TABLE tiger_data.TX_zip_lookup_base ADD CONSTRAINT chk_statefp CHECK (statefp = '48');"
%PSQL% -c "CREATE INDEX idx_tiger_data_TX_zip_lookup_base_citysnd ON tiger_data.TX_zip_lookup_base USING btree(soundex(city));"

echo === DONE ===
