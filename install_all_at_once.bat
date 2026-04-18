@echo off
setlocal
set "ROOT=%~dp0"
cmd /d /c ""%ROOT%scripts\install-core.bat" %*"
exit /b %ERRORLEVEL%
