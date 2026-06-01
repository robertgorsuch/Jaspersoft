@echo off
set WGETTOOL=C:\WINDOWS\system32\curl.exe
set UNZIPTOOL="C:\Program Files\7-Zip\7z.exe"
set T=C:\gisdata\verifytest
if not exist "%T%" mkdir "%T%"

echo --- CASE 1: valid file (should report OK) ---
call :getverified "%T%\good.zip" "https://www2.census.gov/geo/tiger/TIGER_RD18/LAYER/ADDR/tl_rd22_48453_addr.zip"

echo --- CASE 2: nonexistent county 48999 (should retry then GAVE UP) ---
call :getverified "%T%\bad.zip" "https://www2.census.gov/geo/tiger/TIGER_RD18/LAYER/ADDR/tl_rd22_48999_addr.zip"

echo --- DONE ---
goto :eof

:getverified
setlocal
set "OUT=%~1"
set "URL=%~2"
set "TRIES=0"
:gv_retry
set /a TRIES+=1
%WGETTOOL% --location --fail --retry 3 --create-dirs -s -S -o "%OUT%" "%URL%" 2>nul
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
