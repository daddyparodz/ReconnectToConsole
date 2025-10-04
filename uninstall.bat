@echo off
setlocal EnableDelayedExpansion

REM Ensure the script is running with administrator privileges
set "__RTC_ELEVATED_FLAG=__RTC_ELEVATED__"
set "__RTC_ELEVATED="
if /I "%~1"=="%__RTC_ELEVATED_FLAG%" (
    set "__RTC_ELEVATED=1"
    shift
)

if not defined __RTC_ELEVATED (
    whoami /groups | findstr /C:"S-1-16-12288" >nul 2>&1
    if errorlevel 1 (
        echo Administrator privileges are required. Requesting elevation...
        set "BAT_THIS=%~f0"
        set "BAT_ORIG_DIR=%~dp0"
        if "!BAT_ORIG_DIR:~-1!"=="\" set "BAT_ORIG_DIR=!BAT_ORIG_DIR:~0,-1!"

        powershell -NoProfile -ExecutionPolicy Bypass -Command ^
            "$ErrorActionPreference = 'Stop';" ^
            "$bat = $env:BAT_THIS;" ^
            "$dir = ($env:BAT_ORIG_DIR).TrimEnd('\\');" ^
            "$flag = '__RTC_ELEVATED__';" ^
            "$cmd = ('set "RTC_INSTALL_SRC={0}" & call "{1}" {2}') -f $dir, $bat, $flag;" ^
            "try {" ^
            "    Start-Process -FilePath $env:COMSPEC -ArgumentList @('/k', $cmd) -Verb RunAs -WorkingDirectory (Split-Path -Path $bat) | Out-Null;" ^
            "    exit 0" ^
            "} catch [System.ComponentModel.Win32Exception] {" ^
            "    exit $_.NativeErrorCode" ^
            "} catch {" ^
            "    exit 1" ^
            "}" ^
            >nul 2>&1

        set "PS_EXIT=!errorlevel!"
        if not "!PS_EXIT!"=="0" (
            if "!PS_EXIT!"=="1223" (
                echo Elevation request was denied by the user.
            ) else (
                echo Failed to obtain administrator privileges or elevation was cancelled.
            )
            exit /b !PS_EXIT!
        )

        exit /b 0
    )
)

:RUN
echo Uninstalling ReconnectToConsole...
echo(

if defined RTC_INSTALL_SRC (
    set "INSTALL_DIR_RAW=%RTC_INSTALL_SRC%"
    set "RTC_INSTALL_SRC="
) else (
    set "INSTALL_DIR_RAW=%~dp0"
)
for %%I in ("%INSTALL_DIR_RAW%") do set "INSTALL_DIR=%%~fI"
if "%INSTALL_DIR:~-1%"=="\" set "INSTALL_DIR=%INSTALL_DIR:~0,-1%"
set "BIN_DIR=%INSTALL_DIR%\bin"

echo Install directory: "%INSTALL_DIR%"
echo Bin directory (removed from PATH): "%BIN_DIR%"
echo(

REM Pre-check: if PATH lacks BIN_DIR and task is missing, report not installed and exit
set "PATH_PRESENT=absent"
for /f "usebackq tokens=* delims=" %%S in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$t=$env:BIN_DIR.TrimEnd('\\');$p=[Environment]::GetEnvironmentVariable('PATH','User');" ^
    "if(-not [string]::IsNullOrWhiteSpace($p) -and (($p -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }) | Where-Object { [string]::Equals($_.TrimEnd('\\'), $t, 'OrdinalIgnoreCase') }).Count -gt 0){'present'}else{'absent'}"` ) do set "PATH_PRESENT=%%S"

set "TASK_EXISTS="
schtasks /query /tn "rtc" >nul 2>&1 && set "TASK_EXISTS=1"

if /I NOT "%PATH_PRESENT%"=="present" if not defined TASK_EXISTS (
    echo ReconnectToConsole is not installed.
    echo(
    pause
    exit
)

echo Removing from user PATH...
set "TARGET_PATH=%BIN_DIR%"
for /f "usebackq tokens=* delims=" %%S in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$target = $env:TARGET_PATH.TrimEnd('\\');" ^
    "$existing = [Environment]::GetEnvironmentVariable('PATH','User');" ^
    "if ([string]::IsNullOrWhiteSpace($existing)) { $segments = @(); } else { $segments = $existing -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' } }" ^
    "$segments = $segments | Where-Object { -not [string]::Equals($_.TrimEnd('\\'), $target, 'OrdinalIgnoreCase') };" ^
    "[Environment]::SetEnvironmentVariable('PATH', ($segments -join ';'), 'User');" ^
    "if ($existing -and (($existing -split ';' | ForEach-Object { $_.Trim() }) | Where-Object { [string]::Equals($_.TrimEnd('\\'), $target, 'OrdinalIgnoreCase') }).Count -gt 0) { 'removed' } else { 'notfound' }"` ) do set "PATH_STATUS=%%S"
set "TARGET_PATH="

if /I "%PATH_STATUS%"=="removed" (
    echo Successfully removed from PATH.
    echo You may need to restart your command prompt for PATH changes to take effect.
) else if /I "%PATH_STATUS%"=="notfound" (
    echo Bin directory was not present in user PATH.
) else (
    echo Failed to update PATH.
)

REM Update current session PATH
set "TARGET_PATH=%BIN_DIR%"
for /f "usebackq tokens=* delims=" %%S in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$target = $env:TARGET_PATH.TrimEnd('\\');" ^
    "$existing = $env:PATH;" ^
    "if ([string]::IsNullOrWhiteSpace($existing)) { $segments = @(); } else { $segments = $existing -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' } }" ^
    "$segments = $segments | Where-Object { -not [string]::Equals($_.TrimEnd('\\'), $target, 'OrdinalIgnoreCase') };" ^
    "Write-Output ($segments -join ';')"` ) do set "PATH=%%S"
set "TARGET_PATH="

echo(

echo Removing scheduled task...
schtasks /query /tn "rtc" >nul 2>&1
if %errorlevel% equ 0 (
    schtasks /delete /tn "rtc" /f >nul 2>&1
    if %errorlevel% equ 0 (
        echo Successfully removed scheduled task 'rtc'.
    ) else (
        echo Failed to remove scheduled task 'rtc'.
    )
) else (
    echo Scheduled task 'rtc' not found.
)

echo(
echo Uninstallation completed!
echo(
echo The script files remain in: "%INSTALL_DIR%"
echo You can manually delete this directory if desired.
echo(

pause
exit
