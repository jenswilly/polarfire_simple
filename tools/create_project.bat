@echo off
rem Create the Libero project from the repository sources (batch, no GUI).
rem Windows counterpart of tools/create_project.sh.
rem
rem   tools\create_project.bat [project_dir]
rem
rem project_dir defaults to <repo>\polarfire_simple and must not exist yet.
rem Close the Libero GUI first: batch Libero needs the license as well.
rem
rem Libero is taken from LIBERO_INSTALL_DIR (default C:\Microchip\Libero_SoC_2026.1).
rem The license must already be reachable, as for the Libero GUI (LM_LICENSE_FILE
rem or the license manager service set up by the Libero installer).
setlocal

if not defined LIBERO_INSTALL_DIR set "LIBERO_INSTALL_DIR=C:\Microchip\Libero_SoC_2026.1"
set "LIBERO_EXE=%LIBERO_INSTALL_DIR%\Libero_SoC\Designer\bin\libero.exe"
if not exist "%LIBERO_EXE%" set "LIBERO_EXE=%LIBERO_INSTALL_DIR%\Libero_SoC\Designer\bin64\libero.exe"
if not exist "%LIBERO_EXE%" (
    echo libero.exe not found under "%LIBERO_INSTALL_DIR%\Libero_SoC\Designer". Set LIBERO_INSTALL_DIR. 1>&2
    exit /b 1
)

rem libero.exe writes nothing to the console on Windows; the log goes to the
rem repository root (*.log is git-ignored).
set "LOG=%~dp0..\create_project.log"
for %%I in ("%LOG%") do set "LOG=%%~fI"
set "SCRIPT=%~dp0..\libero\create_project.tcl"
for %%I in ("%SCRIPT%") do set "SCRIPT=%%~fI"

rem Run from the repository root: create_project.tcl changes into the new
rem project folder itself once it exists.
pushd "%~dp0.."
if "%~1"=="" (
    "%LIBERO_EXE%" "SCRIPT:%SCRIPT%" "LOGFILE:%LOG%"
) else (
    "%LIBERO_EXE%" "SCRIPT:%SCRIPT%" "LOGFILE:%LOG%" "SCRIPT_ARGS:%~f1"
)
set "RC=%ERRORLEVEL%"
popd
echo Libero exit code %RC%. Log: "%LOG%"
exit /b %RC%
