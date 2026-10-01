@echo off
REM ============================================================
REM  HCIS - Government box
REM  STEP 1 - find out why the sign in is refused. Changes nothing.
REM ============================================================
setlocal
set HERE=%~dp0
REM The database password is no longer written in here - these files are
REM published publicly. It is read from the machine instead, put there once
REM by SET-DB-PASSWORD.bat.
set PGPASSWORD=
if exist "C:\HCIS\db-password.txt" set /p PGPASSWORD=<"C:\HCIS\db-password.txt"
if not defined PGPASSWORD (
  echo.
  echo   The database password has not been set up on this machine yet.
  echo   Run SET-DB-PASSWORD.bat once, then run this again.
  echo.
  pause
  exit /b 1
)
set DB=hcis_db
set DBUSER=postgres
set SITE=C:\HCIS\wwwroot

set PGBIN=
for %%D in (
  "C:\PostgreSQL\16\bin"
  "C:\PostgreSQL\17\bin"
  "C:\Program Files\PostgreSQL\16\bin"
  "C:\Program Files\PostgreSQL\17\bin"
) do (
  if exist "%%~D\psql.exe" if not defined PGBIN set PGBIN=%%~D
)
if not defined PGBIN (
  echo.
  echo   ERROR: psql.exe was not found.
  echo   Look for the PostgreSQL bin folder on this machine and add it to
  echo   the list at the top of this file, then run it again.
  echo.
  goto :end
)
set PSQL=%PGBIN%\psql.exe

REM Running this straight out of the zip viewer copies this file alone to a
REM temp folder and leaves the sql folder behind. Say so plainly rather than
REM letting psql fail with something that reads like a database fault.
if not exist "%HERE%sql\diagnose.sql" (
  echo.
  echo   ------------------------------------------------------------
  echo   This is not unpacked.
  echo.
  echo   The sql folder is not next to this file, which normally means
  echo   it is being run from inside the zip. Windows copies only the
  echo   one file out, so the rest of the package is not there.
  echo.
  echo   Right-click the zip, choose Extract All, put it somewhere like
  echo   C:\HCIS_update, then run this from THAT folder.
  echo   ------------------------------------------------------------
  echo.
  goto :end
)

set REPORT=%HERE%HCIS-login-report.txt
if exist "%REPORT%" del "%REPORT%"

echo.
echo   Reading the Government database. Nothing is changed.
echo.

"%PSQL%" -q -U %DBUSER% -d %DB% -f "%HERE%sql\diagnose.sql" > "%REPORT%" 2>&1

echo === 6. What address does the browser use on this box? ===  >> "%REPORT%"
if exist "%SITE%\config.js" (
  type "%SITE%\config.js"                                       >> "%REPORT%"
) else (
  echo.                                                         >> "%REPORT%"
  echo   config.js IS MISSING FROM %SITE%                        >> "%REPORT%"
  echo   Without it the page talks to the wrong database and the >> "%REPORT%"
  echo   sign in will be refused no matter what the password is. >> "%REPORT%"
)

REM The database half of the report is true and not sufficient - the browser
REM reaches the database THROUGH PostgREST, which can be missing a function the
REM database definitely has. Walk the browser's path too.
if exist "%HERE%check-api.ps1" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%check-api.ps1" >> "%REPORT%" 2>&1
)

type "%REPORT%"
echo.
echo   ------------------------------------------------------------
echo   This is also saved as:
echo     %REPORT%
echo   Send me that file and I will tell you exactly what is wrong.
echo   ------------------------------------------------------------
echo.

:end
pause
