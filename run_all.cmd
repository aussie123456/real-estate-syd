@echo off
rem Full refresh: reference feeds -> parse VG zips -> geocode -> build dashboard data.
rem Double-click, or run from a terminal in this folder. Needs Git for Windows (bash, perl, curl, unzip).
set BASH="C:\Program Files\Git\bin\bash.exe"
cd /d "%~dp0"
%BASH% scripts/fetch_ref.sh
%BASH% scripts/parse_vg.sh
%BASH% scripts/geocode.sh
%BASH% -c "perl scripts/build.pl"
echo.
echo Done. Open dashboard\index.html in your browser.
pause
