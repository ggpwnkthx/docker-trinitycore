@echo off
powershell.exe -executionpolicy bypass -file %~n0.ps1 %*
pause