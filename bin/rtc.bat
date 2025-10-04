@echo off
schtasks /run /tn rtc >nul 2>&1
if errorlevel 1 (
  echo Failed to start scheduled task 'rtc'.
  exit /b 1
)
exit
