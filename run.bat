@echo off
powershell.exe -executionpolicy bypass -file scripts/build.ps1 %*
powershell.exe -executionpolicy bypass -file scripts/add_project.ps1 %*
powershell.exe -executionpolicy bypass -file scripts/start_project.ps1 %*
pause