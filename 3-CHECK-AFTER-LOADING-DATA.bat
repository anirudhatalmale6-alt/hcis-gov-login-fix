@echo off
REM ============================================================
REM  HCIS - run this AFTER loading a database from the old
REM  system, and BEFORE anyone opens payroll.
REM
REM  Reads only. Changes nothing.
REM
REM  It checks the one thing no screen will tell you honestly:
REM  whether the care giver links actually point at care givers
REM  who exist on this machine. A load carrying the old system's
REM  numbering looks completely normal and pays nobody.
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
  echo   ERROR: psql.exe was not found. Add the PostgreSQL bin folder
  echo   to the list at the top of this file and run it again.
  echo.
  goto :end
)
set PSQL=%PGBIN%\psql.exe

if not exist "%HERE%sql\check_load.sql" (
  echo.
  echo   ------------------------------------------------------------
  echo   This is not unpacked.
  echo.
  echo   The sql folder is not next to this file, which normally means
  echo   it is being run from inside the zip. Right-click the zip,
  echo   choose Extract All, then run it from THAT folder.
  echo   ------------------------------------------------------------
  echo.
  goto :end
)

set REPORT=%HERE%HCIS-load-check.txt
if exist "%REPORT%" del "%REPORT%"

"%PSQL%" -q -U %DBUSER% -d %DB% -f "%HERE%sql\check_load.sql" > "%REPORT%" 2>&1
type "%REPORT%"

echo.
echo   ------------------------------------------------------------
echo   Saved as: %REPORT%
echo   If the verdict is not PASS, send me that file before
echo   anybody runs payroll.
echo   ------------------------------------------------------------
echo.

:end
pause
