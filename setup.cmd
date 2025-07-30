@echo off
title Dotfiles Setup
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File "%~dp0bin\manager.ps1"
pause
