@echo off
powershell.exe -executionpolicy bypass -file build.ps1 %*
powershell.exe -executionpolicy bypass -file add_project.ps1 %*
powershell.exe -executionpolicy bypass -file start_project.ps1 %*
pause