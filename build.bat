@echo off
setlocal
REM MEGA65 build: build assets, assemble with 64tass, write the D81 with c1541.
REM The app is the first file on the disk (Xemu -autoload RUNs the first file) and is also
REM written as AUTOBOOT.C65, which a real MEGA65 starts from the mounted disk.
REM   build.bat            the real app (target\weather65.d81)
REM   build.bat mock DIR   Xemu replay build: captured HTTP responses from DIR replace the network
set PROJECT=weather65
if not exist target mkdir target
REM c1541 writes its settings under the user profile: keep them inside target\
if not exist target\userprofile\AppData\Roaming mkdir target\userprofile\AppData\Roaming
set "USERPROFILE=%CD%\target\userprofile"
set "APPDATA=%USERPROFILE%\AppData\Roaming"

del target\*.d81 2>nul
del target\*.lst 2>nul
del target\*.lbl 2>nul
del target\%PROJECT% 2>nul

set MOCKDEF=
set MOCKARG=
if /i "%~1"=="mock" (
    set MOCKDEF=-D MOCK_NET=1
    set "MOCKARG=--mock %~2"
)

python tools\build_assets.py %MOCKARG%
if errorlevel 1 exit /b 1

.\64tass.exe --cbm-prg -C -I src %MOCKDEF% src\main.asm -l target\%PROJECT%.lbl -L target\%PROJECT%.lst -o target\%PROJECT%
if errorlevel 1 exit /b 1

cd target
..\c1541.exe -format "%PROJECT%,01" d81 %PROJECT%.d81 >nul
if errorlevel 1 (cd .. & exit /b 1)
..\c1541.exe -attach %PROJECT%.d81 -write %PROJECT% %PROJECT% >nul
if errorlevel 1 (cd .. & exit /b 1)
..\c1541.exe -attach %PROJECT%.d81 -write %PROJECT% autoboot.c65 >nul
if errorlevel 1 (cd .. & exit /b 1)
REM asset files listed by tools\build_assets.py (written lower case = PETSCII upper case)
if exist assets\files.txt for /f %%f in (assets\files.txt) do (
    ..\c1541.exe -attach %PROJECT%.d81 -write assets\%%f %%f >nul
    if errorlevel 1 (echo failed writing %%f & cd .. & exit /b 1)
)
cd ..

REM keep only the D81, the listing and the labels (the Xemu test harness reads them)
for %%f in (target\*) do (
    if /i not "%%~xf"==".d81" if /i not "%%~xf"==".lst" if /i not "%%~xf"==".lbl" del "%%f"
)
for /d %%d in (target\*) do rmdir /s /q "%%d"

echo Built target\%PROJECT%.d81
