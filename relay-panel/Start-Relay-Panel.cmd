@echo off
cd /d "%~dp0"
if exist RdpFreeRelay.exe (
  RdpFreeRelay.exe
) else (
  py -3 relay_panel.py
)
if errorlevel 1 pause
