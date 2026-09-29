@echo off
REM ============================================================
REM  HCIS - Government box
REM  STEP 2 - put your own sign in back into service.
REM
REM  Calls reset-login.ps1, which asks for the username and a
REM  new password. The password is typed masked and is not
REM  shown on screen.
REM ============================================================
setlocal
set HERE=%~dp0

if not exist "%HERE%reset-login.ps1" (
  echo.
  echo   ------------------------------------------------------------
  echo   This is not unpacked.
  echo.
  echo   reset-login.ps1 is not next to this file, which normally
  echo   means it is being run from inside the zip. Windows copies
  echo   only the one file out, so the rest is not there.
  echo.
  echo   Right-click the zip, choose Extract All, put it somewhere
  echo   like C:\HCIS_update, then run this from THAT folder.
  echo   ------------------------------------------------------------
  echo.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%reset-login.ps1"

echo.
pause
