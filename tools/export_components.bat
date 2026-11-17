@echo off
rem Export the components of the Libero project (HDL+ cores, IP cores, SmartDesign
rem TOP) to libero\components\*.tcl (batch, no GUI). Windows counterpart of
rem tools/export_components.sh. Run it after changing a component and commit the
rem result; libero\create_project.tcl sources these files.
rem
rem   tools\export_components.bat [project.prjx]
rem
rem Close the Libero GUI first: batch Libero needs the license as well, and the
rem GUI may hold unsaved changes.
rem
rem Libero is taken from LIBERO_INSTALL_DIR (default C:\Microchip\Libero_SoC_2026.1).
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
set "LOG=%~dp0..\export_components.log"
for %%I in ("%LOG%") do set "LOG=%%~fI"
set "SCRIPT=%~dp0..\libero\export_components.tcl"
for %%I in ("%SCRIPT%") do set "SCRIPT=%%~fI"
if "%~1"=="" (
    set "PRJX=%~dp0..\polarfire_simple\polarfire_simple.prjx"
) else (
    set "PRJX=%~f1"
)
for %%I in ("%PRJX%") do set "PRJX=%%~fI"
if not exist "%PRJX%" (
    echo Project file "%PRJX%" not found. 1>&2
    exit /b 1
)

rem Run Libero from inside the project folder: it saves some files (HDL+ core
rem definitions under component\User\) relative to its working directory.
for %%I in ("%PRJX%") do pushd "%%~dpI"
"%LIBERO_EXE%" "SCRIPT:%SCRIPT%" "LOGFILE:%LOG%" "SCRIPT_ARGS:%PRJX%"
set "RC=%ERRORLEVEL%"
popd
echo Libero exit code %RC%. Log: "%LOG%"
exit /b %RC%
