@echo off
rem Installieren.bat - startet den Installer als Administrator (UAC-Abfrage erscheint automatisch).
rem Am Ende erscheint eine Abschlussmeldung mit OK, danach schliesst sich das Fenster von selbst.
fltmc >nul 2>&1
if errorlevel 1 (
  echo Administratorrechte erforderlich. Die UAC-Abfrage wird geoeffnet...
  powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
set "SCRIPT="
for %%F in ("%~dp0Install-PatchPilot.ps1") do set "SCRIPT=%%~fF"
if not defined SCRIPT (
  call :msg "Install-PatchPilot.ps1 liegt nicht neben dieser Datei." Warning
  exit /b 2
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
set "RC=%errorlevel%"
if "%RC%"=="0" (
  call :msg "Installation abgeschlossen." Information
) else (
  call :msg "Installation fehlgeschlagen - Code %RC%. Details: C:\Fernwartung\PatchPilot\Logs, Datei PatchPilot_Jahr-Monat.log" Warning
)
exit /b %RC%

:msg
powershell.exe -NoProfile -Command "Add-Type -AssemblyName System.Windows.Forms; $f=New-Object System.Windows.Forms.Form; $f.TopMost=$true; [void][System.Windows.Forms.MessageBox]::Show($f,'%~1','Patch Pilot','OK','%~2')"
exit /b
