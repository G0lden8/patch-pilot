@echo off
rem Test-Neustart.bat - NUR ZUM TESTEN. Loest einen echten Neustart aus, ohne etwas zu installieren.
rem Am Ende erscheint eine Abschlussmeldung mit OK, danach schliesst sich das Fenster von selbst.
fltmc >nul 2>&1
if errorlevel 1 (
  echo Administratorrechte erforderlich. Die UAC-Abfrage wird geoeffnet...
  powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
set "RUN="
for %%F in ("C:\Fernwartung\PatchPilot\Update-Run.ps1") do set "RUN=%%~fF"
if not defined RUN (
  call :msg "Update-Run nicht gefunden. Bitte zuerst Installieren.bat ausfuehren." Warning
  exit /b 2
)
echo.
echo TESTLAUF: Es wird NICHTS installiert. Der PC startet in 60 Sekunden neu.
echo Abbruch nach dem Start: Notaus.bat im Programmordner.
echo.
set /p ANTWORT=Fortfahren? J oder N: 
if /i not "%ANTWORT%"=="J" exit /b 1
set /p AUS=Nach dem Neustart den PC ausschalten? J oder N: 
set "EXTRA="
if /i "%AUS%"=="J" set "EXTRA=-ShutdownAfter"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%RUN%" -Mode Manual -TestReboot %EXTRA%
set "RC=%errorlevel%"
if "%RC%"=="0" (
  call :msg "Testlauf gestartet. Der PC startet in 60 Sekunden neu." Information
) else (
  call :msg "Testlauf fehlgeschlagen - Code %RC%. Details: C:\Fernwartung\PatchPilot\Logs" Warning
)
exit /b %RC%

:msg
powershell.exe -NoProfile -Command "Add-Type -AssemblyName System.Windows.Forms; $f=New-Object System.Windows.Forms.Form; $f.TopMost=$true; [void][System.Windows.Forms.MessageBox]::Show($f,'%~1','Patch Pilot','OK','%~2')"
exit /b
