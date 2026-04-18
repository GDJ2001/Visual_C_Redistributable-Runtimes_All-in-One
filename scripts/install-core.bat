@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "APP_NAME=Microsoft Visual C++ Redistributable All-in-One"
set "DISPLAY_CMD=%~nx0"
if /i "%DISPLAY_CMD%"=="install-core.bat" set "DISPLAY_CMD=install_all_at_once.bat"
set "PS_EXE=powershell"
where pwsh.exe >nul 2>&1 && set "PS_EXE=pwsh"
set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "ROOT=%%~fI\"

set "INSTALL_SET=all"
set "REQUESTED_SET=all"
set "COMPAT_TARGET="
set "TARGET_ARCH=auto"
set "INSTALL_MODE=install"
set "UI_MODE=passive"
set "DRY_RUN=0"
set "VERIFY_ONLY=0"
set "ASSUME_YES=0"
set "NO_RESTART=1"
set "LOG_DIR="
set "SHOW_HELP=0"
set "INTERACTIVE=0"
set "TARGET_X86=0"
set "TARGET_X64=0"
set "TARGET_ARM=0"
set "TARGET_ARM64=0"
set "TARGET_IA64=0"
set "MISSING=0"
set "FAILURES=0"
set "REBOOT_REQUIRED=0"
set "INSTALLED=0"
set "SKIPPED=0"
set "ELEVATED_RUN_DONE=0"

if "%~1"=="" set "INTERACTIVE=1"
goto ParseArgs

:ArgsParsed
if "%SHOW_HELP%"=="1" (
    call :PrintHelp
    exit /b 0
)

if "%INTERACTIVE%"=="1" call :InteractiveMenu
if "%SHOW_HELP%"=="1" exit /b 0

call :ResolveArchitecture
if errorlevel 1 exit /b 1

call :PrepareLogDirectory
if errorlevel 1 exit /b 1

call :WriteHeader
call :ProcessPackages check

if "%MISSING%"=="1" (
    echo.
    echo One or more required redistributable files are missing. No installers were started.
    echo See summary: "%SUMMARY_FILE%"
    exit /b 2
)

if "%VERIFY_ONLY%"=="1" (
    call :VerifySelectedBundle
    if errorlevel 1 (
        echo.
        echo Bundle verification failed. No installers were started.
        echo See summary: "%SUMMARY_FILE%"
        exit /b 3
    )
    echo.
    echo Bundle verification completed successfully. No installers were started.
    call :PrintSummary
    exit /b 0
)

if "%DRY_RUN%"=="1" (
    echo.
    echo Dry run mode. No installers will be launched.
    call :ProcessPackages dry
    call :PrintSummary
    exit /b 0
)

call :ConfirmDiscontinuedInstall
if errorlevel 1 exit /b 6

call :VerifySelectedBundle
if errorlevel 1 (
    echo.
    echo Bundle verification failed. No installers were started.
    echo See summary: "%SUMMARY_FILE%"
    exit /b 3
)

call :EnsureAdministrator
set "ADMIN_EXIT=%ERRORLEVEL%"
if "%ELEVATED_RUN_DONE%"=="1" exit /b %ADMIN_EXIT%
if not "%ADMIN_EXIT%"=="0" exit /b %ADMIN_EXIT%

echo.
echo Installing selected packages...
call :ProcessPackages install
call :PrintSummary

if not "%FAILURES%"=="0" exit /b 1
if "%REBOOT_REQUIRED%"=="1" exit /b 3010
exit /b 0

:ParseArgs
if "%~1"=="" goto ArgsParsed
set "ARG=%~1"

if /i "!ARG!"=="/?" set "SHOW_HELP=1" & shift & goto ParseArgs
if /i "!ARG!"=="/help" set "SHOW_HELP=1" & shift & goto ParseArgs
if /i "!ARG!"=="-help" set "SHOW_HELP=1" & shift & goto ParseArgs

if /i "!ARG!"=="/silent" set "UI_MODE=silent" & shift & goto ParseArgs
if /i "!ARG!"=="/passive" set "UI_MODE=passive" & shift & goto ParseArgs
if /i "!ARG!"=="/dry-run" set "DRY_RUN=1" & shift & goto ParseArgs
if /i "!ARG!"=="/verify-only" set "VERIFY_ONLY=1" & shift & goto ParseArgs
if /i "!ARG!"=="/yes" set "ASSUME_YES=1" & shift & goto ParseArgs
if /i "!ARG!"=="/assume-yes" set "ASSUME_YES=1" & shift & goto ParseArgs
if /i "!ARG!"=="/no-restart" set "NO_RESTART=1" & shift & goto ParseArgs

if /i "!ARG:~0,6!"=="/arch:" (
    set "TARGET_ARCH=!ARG:~6!"
    shift
    goto ParseArgs
)

if /i "!ARG:~0,5!"=="/set:" (
    set "INSTALL_SET=!ARG:~5!"
    shift
    goto ParseArgs
)

if /i "!ARG:~0,6!"=="/mode:" (
    set "INSTALL_MODE=!ARG:~6!"
    shift
    goto ParseArgs
)

if /i "!ARG:~0,9!"=="/log-dir:" (
    set "LOG_DIR=!ARG:~9!"
    shift
    goto ParseArgs
)

if /i "!ARG!"=="/log-dir" goto ParseLogDirArgument

echo Unknown argument: !ARG!
echo Run "%~nx0 /?" for usage.
exit /b 1

:ParseLogDirArgument
shift
if "%~1"=="" (
    echo Missing value for /log-dir.
    exit /b 1
)
set "LOG_DIR=%~1"
shift
goto ParseArgs

:InteractiveMenu
cls
echo %APP_NAME%
echo Developed by GDJ2001
echo.
echo Select package set:
echo   1. All packages       ^(legacy + modern, safe default^)
echo   2. Modern only        ^(shared VC14 runtime family^)
echo   3. VS 2017 / v141    ^(VC14 compatibility target^)
echo   4. VS 2019 / v142    ^(VC14 compatibility target^)
echo   5. VS 2022 / v143    ^(VC14 compatibility target^)
echo   6. Legacy only        ^(2005, 2008, 2010, 2012, 2013^)
echo   7. Discontinued only  ^(VS.NET-era, IA64/ARM, frozen 2015^)
echo   8. Everything         ^(modern + legacy + discontinued^)
echo   9. Dry run preview
echo   10. Verify bundle only
echo   H. Help
echo.
set /p "MENU_SET=Choose [1]: "
if not defined MENU_SET set "MENU_SET=1"
if /i "%MENU_SET%"=="H" (
    set "SHOW_HELP=1"
    call :PrintHelp
    exit /b 0
)
if "%MENU_SET%"=="1" set "INSTALL_SET=all"
if "%MENU_SET%"=="2" set "INSTALL_SET=modern"
if "%MENU_SET%"=="3" set "INSTALL_SET=v141"
if "%MENU_SET%"=="4" set "INSTALL_SET=v142"
if "%MENU_SET%"=="5" set "INSTALL_SET=v143"
if "%MENU_SET%"=="6" set "INSTALL_SET=legacy"
if "%MENU_SET%"=="7" set "INSTALL_SET=discontinued"
if "%MENU_SET%"=="8" set "INSTALL_SET=everything"
if "%MENU_SET%"=="9" set "DRY_RUN=1"
if "%MENU_SET%"=="10" set "VERIFY_ONLY=1"

echo.
echo Select architecture:
echo   1. Auto-detect
echo   2. x86 only
echo   3. x86 + x64
echo   4. ARM only
echo   5. ARM64 OS ^(x86 + x64 + ARM64^)
echo   6. IA64 OS ^(x86 + IA64^)
echo   7. Any package architecture
echo.
set /p "MENU_ARCH=Choose [1]: "
if not defined MENU_ARCH set "MENU_ARCH=1"
if "%MENU_ARCH%"=="1" set "TARGET_ARCH=auto"
if "%MENU_ARCH%"=="2" set "TARGET_ARCH=x86"
if "%MENU_ARCH%"=="3" set "TARGET_ARCH=x64"
if "%MENU_ARCH%"=="4" set "TARGET_ARCH=arm"
if "%MENU_ARCH%"=="5" set "TARGET_ARCH=arm64"
if "%MENU_ARCH%"=="6" set "TARGET_ARCH=ia64"
if "%MENU_ARCH%"=="7" set "TARGET_ARCH=any"

echo.
echo Select installer UI:
echo   1. Passive progress windows
echo   2. Silent background install
echo.
set /p "MENU_UI=Choose [1]: "
if not defined MENU_UI set "MENU_UI=1"
if "%MENU_UI%"=="1" set "UI_MODE=passive"
if "%MENU_UI%"=="2" set "UI_MODE=silent"

echo.
set /p "MENU_MODE=Install mode [install/repair, default install]: "
if not defined MENU_MODE set "MENU_MODE=install"
set "INSTALL_MODE=%MENU_MODE%"
exit /b 0

:PrintHelp
echo.
echo %APP_NAME%
echo.
echo Usage:
echo   %DISPLAY_CMD% [options]
echo.
echo Options:
echo   /silent                  Run installers with quiet UI where supported.
echo   /passive                 Run installers with passive progress UI. Default.
echo   /dry-run                 Show selected packages without installing.
echo   /verify-only             Validate selected bundled EXEs, hashes, and signatures.
echo   /yes                     Confirm prompts for automation.
echo   /no-restart              Prevent redistributables from restarting Windows. Default.
echo   /arch:x86^|x64^|arm^|arm64^|ia64^|any^|auto
echo                            Select package architecture. Default auto.
echo   /set:all^|modern^|legacy^|discontinued^|everything
echo                            Select package group. Default all.
echo   /set:v141^|v142^|v143^|2017^|2019^|2022
echo                            Install the shared VC14 runtime for a specific VS toolset target.
echo   /mode:install^|repair     Install or repair where supported. Default install.
echo   /log-dir:^<path^>          Write run logs to a custom directory.
echo   /log-dir ^<path^>          Alternate form for paths with spaces.
echo   Help options             /? or /help.
echo.
echo Examples:
echo   %DISPLAY_CMD% /dry-run
echo   %DISPLAY_CMD% /verify-only
echo   %DISPLAY_CMD% /silent /set:modern /arch:auto
echo   %DISPLAY_CMD% /silent /yes /set:modern
echo   %DISPLAY_CMD% /silent /yes /set:v141
echo   %DISPLAY_CMD% /silent /yes /set:v142
echo   %DISPLAY_CMD% /silent /yes /set:v143
echo   %DISPLAY_CMD% /dry-run /set:discontinued /arch:any
echo   %DISPLAY_CMD% /set:discontinued /arch:any
echo   %DISPLAY_CMD% /passive /mode:repair "/log-dir:C:\Temp\VC Logs"
echo   %DISPLAY_CMD% /dry-run /log-dir "C:\Temp\VC Logs"
echo.
exit /b 0

:ResolveArchitecture
call :NormalizeInstallSet
if errorlevel 1 exit /b 1

if /i "%INSTALL_SET%"=="all" goto SetOk
if /i "%INSTALL_SET%"=="modern" goto SetOk
if /i "%INSTALL_SET%"=="legacy" goto SetOk
if /i "%INSTALL_SET%"=="discontinued" goto SetOk
if /i "%INSTALL_SET%"=="everything" goto SetOk
echo Invalid /set value: %INSTALL_SET%
exit /b 1

:NormalizeInstallSet
set "REQUESTED_SET=%INSTALL_SET%"
set "COMPAT_TARGET="
if /i "%INSTALL_SET%"=="2017" set "INSTALL_SET=modern" & set "COMPAT_TARGET=Visual Studio 2017 / v141 final"
if /i "%INSTALL_SET%"=="vs2017" set "INSTALL_SET=modern" & set "COMPAT_TARGET=Visual Studio 2017 / v141 final"
if /i "%INSTALL_SET%"=="v141" set "INSTALL_SET=modern" & set "COMPAT_TARGET=Visual Studio 2017 / v141 final"
if /i "%INSTALL_SET%"=="vc141" set "INSTALL_SET=modern" & set "COMPAT_TARGET=Visual Studio 2017 / v141 final"
if /i "%INSTALL_SET%"=="v141-final" set "INSTALL_SET=modern" & set "COMPAT_TARGET=Visual Studio 2017 / v141 final"
if /i "%INSTALL_SET%"=="2019" set "INSTALL_SET=modern" & set "COMPAT_TARGET=Visual Studio 2019 / v142 final"
if /i "%INSTALL_SET%"=="vs2019" set "INSTALL_SET=modern" & set "COMPAT_TARGET=Visual Studio 2019 / v142 final"
if /i "%INSTALL_SET%"=="v142" set "INSTALL_SET=modern" & set "COMPAT_TARGET=Visual Studio 2019 / v142 final"
if /i "%INSTALL_SET%"=="vc142" set "INSTALL_SET=modern" & set "COMPAT_TARGET=Visual Studio 2019 / v142 final"
if /i "%INSTALL_SET%"=="v142-final" set "INSTALL_SET=modern" & set "COMPAT_TARGET=Visual Studio 2019 / v142 final"
if /i "%INSTALL_SET%"=="2022" set "INSTALL_SET=modern" & set "COMPAT_TARGET=Visual Studio 2022 / v143 final"
if /i "%INSTALL_SET%"=="vs2022" set "INSTALL_SET=modern" & set "COMPAT_TARGET=Visual Studio 2022 / v143 final"
if /i "%INSTALL_SET%"=="v143" set "INSTALL_SET=modern" & set "COMPAT_TARGET=Visual Studio 2022 / v143 final"
if /i "%INSTALL_SET%"=="vc143" set "INSTALL_SET=modern" & set "COMPAT_TARGET=Visual Studio 2022 / v143 final"
if /i "%INSTALL_SET%"=="v143-final" set "INSTALL_SET=modern" & set "COMPAT_TARGET=Visual Studio 2022 / v143 final"
exit /b 0

:SetOk
if /i "%INSTALL_MODE%"=="install" goto ModeOk
if /i "%INSTALL_MODE%"=="repair" goto ModeOk
echo Invalid /mode value: %INSTALL_MODE%
exit /b 1

:ModeOk
if /i "%UI_MODE%"=="passive" goto UiOk
if /i "%UI_MODE%"=="silent" goto UiOk
echo Invalid UI mode: %UI_MODE%
exit /b 1

:UiOk
if /i "%TARGET_ARCH%"=="auto" (
    set "TARGET_ARCH=x86"
    if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" set "TARGET_ARCH=x64"
    if /i "%PROCESSOR_ARCHITECTURE%"=="ARM" set "TARGET_ARCH=arm"
    if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "TARGET_ARCH=arm64"
    if /i "%PROCESSOR_ARCHITECTURE%"=="IA64" set "TARGET_ARCH=ia64"
    if /i "%PROCESSOR_ARCHITEW6432%"=="AMD64" set "TARGET_ARCH=x64"
    if /i "%PROCESSOR_ARCHITEW6432%"=="ARM64" set "TARGET_ARCH=arm64"
    if /i "%PROCESSOR_ARCHITEW6432%"=="IA64" set "TARGET_ARCH=ia64"
)

if /i "%TARGET_ARCH%"=="x86" (
    set "TARGET_X86=1"
    set "TARGET_X64=0"
    exit /b 0
)

if /i "%TARGET_ARCH%"=="x64" (
    set "TARGET_X86=1"
    set "TARGET_X64=1"
    exit /b 0
)

if /i "%TARGET_ARCH%"=="arm" (
    set "TARGET_ARM=1"
    exit /b 0
)

if /i "%TARGET_ARCH%"=="arm64" (
    set "TARGET_X86=1"
    set "TARGET_X64=1"
    set "TARGET_ARM64=1"
    exit /b 0
)

if /i "%TARGET_ARCH%"=="ia64" (
    set "TARGET_X86=1"
    set "TARGET_IA64=1"
    exit /b 0
)

if /i "%TARGET_ARCH%"=="any" (
    set "TARGET_X86=1"
    set "TARGET_X64=1"
    set "TARGET_ARM=1"
    set "TARGET_ARM64=1"
    set "TARGET_IA64=1"
    exit /b 0
)

echo Invalid /arch value: %TARGET_ARCH%
exit /b 1

:PrepareLogDirectory
for /f %%I in ('%PS_EXE% -NoProfile -NonInteractive -Command "Get-Date -Format yyyyMMdd-HHmmss-fff"') do set "RUN_ID=%%I"
if not defined RUN_ID set "RUN_ID=run"
set "RUN_ID=%RUN_ID%-%RANDOM%"

set "REQUESTED_LOG_DIR=%LOG_DIR%"
if not defined REQUESTED_LOG_DIR set "REQUESTED_LOG_DIR=%TEMP%\VisualCRedistAIO\Logs"
call :TryLogDirectory "%REQUESTED_LOG_DIR%"
if errorlevel 1 (
    echo Could not use requested log directory: "%REQUESTED_LOG_DIR%"
    echo Falling back to "%TEMP%\VisualCRedistAIO\Logs"
    call :TryLogDirectory "%TEMP%\VisualCRedistAIO\Logs"
)

if errorlevel 1 (
    echo Could not create log directory.
    exit /b 1
)

set "SUMMARY_FILE=%LOG_DIR%\summary-%RUN_ID%.txt"
exit /b 0

:TryLogDirectory
set "CANDIDATE_LOG_DIR=%~1"
mkdir "%CANDIDATE_LOG_DIR%" >nul 2>&1
if not exist "%CANDIDATE_LOG_DIR%\." exit /b 1
set "LOG_TEST_FILE=%CANDIDATE_LOG_DIR%\write-test-%RANDOM%.tmp"
> "%LOG_TEST_FILE%" echo test
if not exist "%LOG_TEST_FILE%" exit /b 1
del /q "%LOG_TEST_FILE%" >nul 2>&1
set "LOG_DIR=%CANDIDATE_LOG_DIR%"
exit /b 0

:WriteHeader
> "%SUMMARY_FILE%" echo %APP_NAME% run summary
>> "%SUMMARY_FILE%" echo Run ID: %RUN_ID%
>> "%SUMMARY_FILE%" echo Root: %ROOT%
>> "%SUMMARY_FILE%" echo Set: %INSTALL_SET%
>> "%SUMMARY_FILE%" echo Requested set: %REQUESTED_SET%
if defined COMPAT_TARGET >> "%SUMMARY_FILE%" echo Compatibility target: %COMPAT_TARGET%
>> "%SUMMARY_FILE%" echo Architecture: %TARGET_ARCH%
>> "%SUMMARY_FILE%" echo Architecture flags: x86=%TARGET_X86% x64=%TARGET_X64% arm=%TARGET_ARM% arm64=%TARGET_ARM64% ia64=%TARGET_IA64%
>> "%SUMMARY_FILE%" echo Mode: %INSTALL_MODE%
>> "%SUMMARY_FILE%" echo UI: %UI_MODE%
>> "%SUMMARY_FILE%" echo Dry run: %DRY_RUN%
>> "%SUMMARY_FILE%" echo Verify only: %VERIFY_ONLY%
>> "%SUMMARY_FILE%" echo.
>> "%SUMMARY_FILE%" echo Package ^| Result ^| ExitCode ^| Log
>> "%SUMMARY_FILE%" echo ------- ^| ------ ^| -------- ^| ---
exit /b 0

:ConfirmDiscontinuedInstall
set "CONFIRM_REQUIRED=0"
if /i "%INSTALL_SET%"=="discontinued" set "CONFIRM_REQUIRED=1"
if /i "%INSTALL_SET%"=="everything" set "CONFIRM_REQUIRED=1"
if "%CONFIRM_REQUIRED%"=="0" exit /b 0
if "%ASSUME_YES%"=="1" exit /b 0
if /i "%UI_MODE%"=="silent" exit /b 0

echo.
echo WARNING: You selected discontinued packages.
echo These packages are kept for compatibility only and may target obsolete Windows or CPU platforms.
echo Type YES to continue, or anything else to cancel.
set /p "DISCONTINUED_CONFIRM=Continue with discontinued packages? "
if /i "%DISCONTINUED_CONFIRM%"=="YES" exit /b 0
echo Cancelled by user before installing discontinued packages.
exit /b 1

:VerifySelectedBundle
echo.
echo Verifying selected redistributable files...
>> "%SUMMARY_FILE%" echo.
>> "%SUMMARY_FILE%" echo Verification:
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%ROOT%scripts\verify-bundle.ps1" -PackageGroup "%INSTALL_SET%" -Architecture "%TARGET_ARCH%"
set "VERIFY_EXIT=%ERRORLEVEL%"
if not "%VERIFY_EXIT%"=="0" (
    call :AppendSummary "Bundle verification" "FAILED" "%VERIFY_EXIT%" "metadata/SHA256SUMS.txt"
    exit /b 1
)
call :AppendSummary "Bundle verification" "SUCCESS" "0" "metadata/SHA256SUMS.txt"
exit /b 0

:EnsureAdministrator
net session >nul 2>&1
if "%ERRORLEVEL%"=="0" exit /b 0

echo.
echo Administrator rights are required. Requesting elevation...
set "ELEVATE_UI_ARG=/passive"
if /i "%UI_MODE%"=="silent" set "ELEVATE_UI_ARG=/silent"
set "ELEVATE_INSTALLER=%~f0"
set "ELEVATE_SET=%REQUESTED_SET%"
set "ELEVATE_ARCH=%TARGET_ARCH%"
set "ELEVATE_MODE=%INSTALL_MODE%"
set "ELEVATE_UI=%ELEVATE_UI_ARG%"
set "ELEVATE_LOG_DIR=%LOG_DIR%"
"%PS_EXE%" -NoProfile -NonInteractive -Command "$argList = @('/set:' + $env:ELEVATE_SET, '/arch:' + $env:ELEVATE_ARCH, '/mode:' + $env:ELEVATE_MODE, $env:ELEVATE_UI, '/yes', '/log-dir', $env:ELEVATE_LOG_DIR); $process = Start-Process -FilePath $env:ELEVATE_INSTALLER -ArgumentList $argList -Verb RunAs -Wait -PassThru; if ($null -eq $process) { exit 5 }; exit $process.ExitCode"
set "ELEVATE_EXIT=%ERRORLEVEL%"
set "ELEVATED_RUN_DONE=1"
if "%ELEVATE_EXIT%"=="0" exit /b 0
if "%ELEVATE_EXIT%"=="3010" exit /b 3010
if "%ELEVATE_EXIT%"=="1223" (
    echo Elevation was cancelled or failed.
    exit /b 5
)
echo Elevated installer exited with code %ELEVATE_EXIT%.
exit /b %ELEVATE_EXIT%

:ProcessPackages
set "ACTION=%~1"
call :Package "%ACTION%" "legacy" "x86" "Visual C++ 2005 x86" "redists\2005\vcredist_x86.exe" "2005"
call :Package "%ACTION%" "legacy" "x64" "Visual C++ 2005 x64" "redists\2005\vcredist_x64.exe" "2005"
call :Package "%ACTION%" "legacy" "x86" "Visual C++ 2008 x86" "redists\2008\vcredist_x86.exe" "2008"
call :Package "%ACTION%" "legacy" "x64" "Visual C++ 2008 x64" "redists\2008\vcredist_x64.exe" "2008"
call :Package "%ACTION%" "legacy" "x86" "Visual C++ 2010 x86" "redists\2010\vcredist_x86.exe" "2010"
call :Package "%ACTION%" "legacy" "x64" "Visual C++ 2010 x64" "redists\2010\vcredist_x64.exe" "2010"
call :Package "%ACTION%" "legacy" "x86" "Visual C++ 2012 x86" "redists\2012\vcredist_x86.exe" "2012"
call :Package "%ACTION%" "legacy" "x64" "Visual C++ 2012 x64" "redists\2012\vcredist_x64.exe" "2012"
call :Package "%ACTION%" "legacy" "x86" "Visual C++ 2013 x86" "redists\2013\vcredist_x86.exe" "2013"
call :Package "%ACTION%" "legacy" "x64" "Visual C++ 2013 x64" "redists\2013\vcredist_x64.exe" "2013"
call :Package "%ACTION%" "modern" "x86" "Visual C++ 2015-2026 x86" "redists\vc14\vc_redist.x86.exe" "vc14"
call :Package "%ACTION%" "modern" "x64" "Visual C++ 2015-2026 x64" "redists\vc14\vc_redist.x64.exe" "vc14"
call :Package "%ACTION%" "modern" "arm64" "Visual C++ 2015-2026 ARM64" "redists\vc14\vc_redist.arm64.exe" "vc14"
call :Package "%ACTION%" "discontinued" "x86" "Visual C++ .NET 2002 MFC70 security update x86" "redists\2002\vs7.0sp1-kb924642-x86.exe" "vs2002"
call :Package "%ACTION%" "discontinued" "x86" "Visual C++ .NET 2003 MFC security update x86" "redists\2003\vs7.1sp1-kb2465373-x86.exe" "vs2003"
call :Package "%ACTION%" "discontinued" "ia64" "Visual C++ 2005 IA64" "redists\2005\vcredist_ia64.exe" "2005"
call :Package "%ACTION%" "discontinued" "ia64" "Visual C++ 2008 IA64" "redists\2008\vcredist_ia64.exe" "2008"
call :Package "%ACTION%" "discontinued" "ia64" "Visual C++ 2010 IA64" "redists\2010\vcredist_ia64.exe" "2010"
call :Package "%ACTION%" "discontinued" "arm" "Visual C++ 2012 ARM" "redists\2012\vcredist_arm.exe" "2012"
call :Package "%ACTION%" "discontinued" "x86" "Visual C++ 2015 Update 3 x86" "redists\2015\vc_redist.x86.exe" "2015"
call :Package "%ACTION%" "discontinued" "x64" "Visual C++ 2015 Update 3 x64" "redists\2015\vc_redist.x64.exe" "2015"
goto :EOF

:Package
set "ACTION=%~1"
set "CATEGORY=%~2"
set "PKG_ARCH=%~3"
set "PKG_NAME=%~4"
set "REL_PATH=%~5"
set "PKG_ID=%~6"

if /i "%INSTALL_SET%"=="all" if /i "%CATEGORY%"=="discontinued" goto :EOF
if /i "%INSTALL_SET%"=="modern" if /i not "%CATEGORY%"=="modern" goto :EOF
if /i "%INSTALL_SET%"=="legacy" if /i not "%CATEGORY%"=="legacy" goto :EOF
if /i "%INSTALL_SET%"=="discontinued" if /i not "%CATEGORY%"=="discontinued" goto :EOF
if /i "%PKG_ARCH%"=="x64" if not "%TARGET_X64%"=="1" goto :EOF
if /i "%PKG_ARCH%"=="x86" if not "%TARGET_X86%"=="1" goto :EOF
if /i "%PKG_ARCH%"=="arm" if not "%TARGET_ARM%"=="1" goto :EOF
if /i "%PKG_ARCH%"=="arm64" if not "%TARGET_ARM64%"=="1" goto :EOF
if /i "%PKG_ARCH%"=="ia64" if not "%TARGET_IA64%"=="1" goto :EOF

set "EXE_PATH=%ROOT%%REL_PATH%"

if /i "%ACTION%"=="check" (
    if not exist "%EXE_PATH%" (
        echo Missing: %REL_PATH%
        call :AppendSummary "%PKG_NAME%" "MISSING" "-" "%REL_PATH%"
        set "MISSING=1"
    )
    goto :EOF
)

if /i "%ACTION%"=="dry" (
    call :AppendSummary "%PKG_NAME%" "DRY-RUN" "-" "%REL_PATH%"
    echo Would run: %REL_PATH%
    goto :EOF
)

if /i "%ACTION%"=="install" call :InstallPackage
goto :EOF

:InstallPackage
if /i "%PKG_ID%"=="vc14" (
    call :IsVc14Current "%PKG_ARCH%" "%EXE_PATH%"
    if "!VC14_CURRENT!"=="1" (
        echo Skipping %PKG_NAME% because an equal or newer VC14 runtime is already installed.
        call :AppendSummary "%PKG_NAME%" "SKIPPED" "0" "Already installed"
        set /a SKIPPED+=1
        exit /b 0
    )
)

call :BuildInstallerArgs "%PKG_ID%"
set "SAFE_NAME=%PKG_NAME: =_%"
set "SAFE_NAME=%SAFE_NAME:/=_%"
set "SAFE_NAME=%SAFE_NAME::=_%"
set "INSTALLER_LOG=%LOG_DIR%\%SAFE_NAME%-%RUN_ID%.log"

echo Running %PKG_NAME%...
echo Command: "%EXE_PATH%" %PACKAGE_ARGS% > "%INSTALLER_LOG%"
"%EXE_PATH%" %PACKAGE_ARGS% >> "%INSTALLER_LOG%" 2>&1
set "EXIT_CODE=%ERRORLEVEL%"

if "%EXIT_CODE%"=="0" (
    call :AppendSummary "%PKG_NAME%" "SUCCESS" "%EXIT_CODE%" "%INSTALLER_LOG%"
    set /a INSTALLED+=1
    exit /b 0
)

if "%EXIT_CODE%"=="3010" (
    call :AppendSummary "%PKG_NAME%" "REBOOT REQUIRED" "%EXIT_CODE%" "%INSTALLER_LOG%"
    set "REBOOT_REQUIRED=1"
    set /a INSTALLED+=1
    exit /b 0
)

if "%EXIT_CODE%"=="1638" (
    call :AppendSummary "%PKG_NAME%" "SKIPPED" "%EXIT_CODE%" "%INSTALLER_LOG%"
    set /a SKIPPED+=1
    exit /b 0
)

call :AppendSummary "%PKG_NAME%" "FAILED" "%EXIT_CODE%" "%INSTALLER_LOG%"
set /a FAILURES+=1
exit /b 0

:BuildInstallerArgs
set "PKG_SWITCH=%~1"
set "PACKAGE_ARGS="

if /i "%PKG_SWITCH%"=="2005" (
    set "PACKAGE_ARGS=/q"
    exit /b 0
)

if /i "%PKG_SWITCH%"=="2008" (
    if /i "%UI_MODE%"=="silent" (
        set "PACKAGE_ARGS=/q"
    ) else (
        set "PACKAGE_ARGS=/qb"
    )
    exit /b 0
)

if /i "%PKG_SWITCH%"=="2010" (
    set "MODE_PREFIX="
    if /i "%INSTALL_MODE%"=="repair" set "MODE_PREFIX=/repair "
    if /i "%UI_MODE%"=="silent" (
        set "PACKAGE_ARGS=%MODE_PREFIX%/q /norestart"
    ) else (
        set "PACKAGE_ARGS=%MODE_PREFIX%/passive /norestart"
    )
    exit /b 0
)

if /i "%PKG_SWITCH%"=="vs2002" (
    set "PACKAGE_ARGS=/quiet /norestart"
    exit /b 0
)

if /i "%PKG_SWITCH%"=="vs2003" (
    set "PACKAGE_ARGS=/quiet /norestart"
    exit /b 0
)

set "MODE_SWITCH=/install"
if /i "%INSTALL_MODE%"=="repair" set "MODE_SWITCH=/repair"
set "DISPLAY_SWITCH=/passive"
if /i "%UI_MODE%"=="silent" set "DISPLAY_SWITCH=/quiet"
set "PACKAGE_ARGS=%MODE_SWITCH% %DISPLAY_SWITCH% /norestart"
exit /b 0

:IsVc14Current
set "VC14_CURRENT=0"
set "VC14_EXE=%~2"
set "VC14_ARCH=%~1"
for /f %%I in ('%PS_EXE% -NoProfile -NonInteractive -Command "$exe=$env:VC14_EXE; $arch=$env:VC14_ARCH; $target=[version]((Get-Item -LiteralPath $exe).VersionInfo.ProductVersion); $key='HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\' + $arch; try { $installed=(Get-ItemProperty -Path $key -ErrorAction Stop).Version -replace '^[vV]',''; if ([version]$installed -ge $target) { '1' } else { '0' } } catch { '0' }"') do set "VC14_CURRENT=%%I"
exit /b 0

:AppendSummary
>> "%SUMMARY_FILE%" echo %~1 ^| %~2 ^| %~3 ^| %~4
exit /b 0

:PrintSummary
echo.
echo Summary:
type "%SUMMARY_FILE%"
echo.
echo Summary saved to: "%SUMMARY_FILE%"
if "%REBOOT_REQUIRED%"=="1" echo A restart is required to finish at least one package.
if not "%FAILURES%"=="0" echo One or more packages failed. Check the logs above.
exit /b 0
