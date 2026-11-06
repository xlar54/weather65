@echo off
call build.bat
if errorlevel 1 exit /b 1

REM Networking does not work in Xemu: the app stops at "NO NETWORK". Use build.bat mock for a UI test.
C:\Emulation\Mega65\xmega65.exe -8 "%~dp0target\weather65.d81" -autoload -hdosvirt -hdosdir "%~dp0target"
