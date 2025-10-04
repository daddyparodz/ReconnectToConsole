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
            "$cmd = ('set RTC_INSTALL_SRC={0} & call \"{1}\" {2}') -f $dir, $bat, $flag;" ^
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

echo Installing ReconnectToConsole...
echo(

REM Determine install directory from original script location
if defined RTC_INSTALL_SRC (
    set "INSTALL_DIR_RAW=%RTC_INSTALL_SRC%"
    set "RTC_INSTALL_SRC="
) else (
    set "INSTALL_DIR_RAW=%~dp0"
)

REM Resolve to absolute path without surrounding quotes
for %%I in ("%INSTALL_DIR_RAW%") do set "INSTALL_DIR=%%~fI"

REM Remove any trailing backslash for canonical form
if "%INSTALL_DIR:~-1%"=="\" set "INSTALL_DIR=%INSTALL_DIR:~0,-1%"

set "BIN_DIR=%INSTALL_DIR%\bin"
set "INSTALL_DIR_RAW="

echo Install directory: "%INSTALL_DIR%"
echo Bin directory (added to PATH): "%BIN_DIR%"
echo(

REM Add to user PATH if not already present
REM Pre-check: if PATH already has BIN_DIR and task exists, report installed and exit
set "PATH_PRESENT=absent"
for /f "usebackq tokens=* delims=" %%S in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$t=$env:BIN_DIR.TrimEnd('\\');$p=[Environment]::GetEnvironmentVariable('PATH','User');" ^
    "if(-not [string]::IsNullOrWhiteSpace($p) -and (($p -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }) | Where-Object { [string]::Equals($_.TrimEnd('\\'), $t, 'OrdinalIgnoreCase') }).Count -gt 0){'present'}else{'absent'}"` ) do set "PATH_PRESENT=%%S"

set "TASK_EXISTS="
schtasks /query /tn "rtc" >nul 2>&1 && set "TASK_EXISTS=1"

if /I "%PATH_PRESENT%"=="present" if defined TASK_EXISTS (
    echo ReconnectToConsole is already installed.
    echo(
    pause
    exit
)

echo Adding to user PATH...
set "USER_PATH="
for /f "usebackq tokens=2*" %%A in (`reg query HKCU\Environment /v PATH 2^>nul`) do set "USER_PATH=%%B"

set "TARGET_PATH=%BIN_DIR%"
for /f "usebackq tokens=* delims=" %%S in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$target = $env:TARGET_PATH.TrimEnd('\\');" ^
    "$existing = [Environment]::GetEnvironmentVariable('PATH','User');" ^
    "$segments = @();" ^
    "if (-not [string]::IsNullOrWhiteSpace($existing)) {" ^
    "    $segments = $existing -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' };" ^
    "    $segments = $segments | Where-Object { -not [string]::Equals($_.TrimEnd('\\'), $target, 'OrdinalIgnoreCase') };" ^
    "} else { $segments = @(); }" ^
    "if (-not ($segments | Where-Object { [string]::Equals($_.TrimEnd('\\'), $target, 'OrdinalIgnoreCase') })) {" ^
    "    $segments += $target;" ^
    "    $status = 'added';" ^
    "} else { $status = 'exists'; }" ^
    "[Environment]::SetEnvironmentVariable('PATH', ($segments -join ';'), 'User');" ^
    "Write-Output $status"` ) do set "PATH_STATUS=%%S"
set "TARGET_PATH="

if /I "%PATH_STATUS%"=="added" (
    echo Successfully added to PATH.
    echo You may need to restart your command prompt for PATH changes to take effect.
) else if /I "%PATH_STATUS%"=="exists" (
    echo Bin directory already in PATH.
) else (
    echo Failed to update PATH.
    exit /b 1
)

REM Ensure current session can see the rtc command immediately
set "TARGET_PATH=%BIN_DIR%"
for /f "usebackq tokens=* delims=" %%S in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$target = $env:TARGET_PATH.TrimEnd('\\');" ^
    "$existing = $env:PATH;" ^
    "$segments = @();" ^
    "if (-not [string]::IsNullOrWhiteSpace($existing)) {" ^
    "    $segments = $existing -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' };" ^
    "    $segments = $segments | Where-Object { -not [string]::Equals($_.TrimEnd('\\'), $target, 'OrdinalIgnoreCase') };" ^
    "} else { $segments = @(); }" ^
    "if (-not ($segments | Where-Object { [string]::Equals($_.TrimEnd('\\'), $target, 'OrdinalIgnoreCase') })) { $segments += $target }" ^
    "Write-Output ($segments -join ';')"` ) do set "PATH=%%S"
set "TARGET_PATH="

echo(

REM Create scheduled task (disabled by default)
echo Creating scheduled task...
set "SCRIPT_PATH=%INSTALL_DIR%\ReconnectToConsole.bat"

REM Check if main script exists
if not exist "%SCRIPT_PATH%" (
    echo Error: ReconnectToConsole.bat not found at: %SCRIPT_PATH%
    echo Installation failed.
    exit /b 1
)

REM Delete existing task if it exists
schtasks /query /tn "rtc" >nul 2>&1
if %errorlevel% equ 0 (
    echo Removing existing scheduled task...
    schtasks /delete /tn "rtc" /f >nul 2>&1
)

REM Determine the fully qualified user account (domain\user)
for /f "delims=" %%I in ('whoami') do set "TASK_PRINCIPAL=%%I"

if not defined TASK_PRINCIPAL (
    echo Failed to determine the current user account for the scheduled task.
    echo Installation failed.
    exit /b 1
)

REM Register scheduled task with correct quoting
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference = 'Stop';" ^
    "$script = Join-Path $env:INSTALL_DIR 'ReconnectToConsole.bat';" ^
    "$action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument ('/c \"' + $script + '\"');" ^
    "$principal = New-ScheduledTaskPrincipal -UserId $env:TASK_PRINCIPAL -LogonType Interactive -RunLevel Highest;" ^
    "$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries;" ^
    "$settings.ExecutionTimeLimit = 'PT0S';" ^
    "$settings.Compatibility = 'Win8';" ^
    "Register-ScheduledTask -TaskName 'rtc' -Action $action -Principal $principal -Settings $settings -Description 'Reconnect remote desktop session to the console' -Force"

if %errorlevel% equ 0 (
    echo Successfully created scheduled task 'rtc'.
) else (
    echo Failed to create scheduled task 'rtc'.
    echo Make sure you have sufficient privileges to create scheduled tasks.
    echo Installation failed.
    exit /b 1
)

echo(
echo Installation completed successfully!
echo(
echo Usage:
echo   rtc  - Reconnect to console via scheduled task
echo(
echo To uninstall, run: uninstall.bat
echo(
pause
exit
