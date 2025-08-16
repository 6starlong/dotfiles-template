@echo off
title Dotfiles Setup
cd /d "%~dp0"
pwsh -ExecutionPolicy Bypass -File "%~dp0bin\manager.ps1"
