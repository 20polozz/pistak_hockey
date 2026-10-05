@echo off
title PISTAK runner
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tool\windows\pistak_runner.ps1"
pause
