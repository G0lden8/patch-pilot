#requires -Version 5.1
<#
=====================================================================
Set-PatchPilot-Funktionsupdates-Clientverwaltung_V0.10.4  (Patch Pilot 0.10.4)
=====================================================================
ZWECK
  Schaltet auf einem PC Funktionsupdates (neue Windows-Version) fuer
  Patch Pilot ein oder aus, ohne Benutzer-Fenster. Gleiche Wirkung wie
  Funktionsupdates-Ein.bat / Funktionsupdates-Aus.bat im Programmordner.

CLIENTVERWALTUNG
  Sprache: PowerShell. Ausfuehren als: System.
  Parameter (Feld "Preset Parameter"):  Ein   oder   Aus
  Standard ohne Parameter: nichts aendern, nur aktuellen Stand anzeigen.

EXITCODES
  0 = erledigt, 1 = nicht als System/Administrator, 2 = Patch Pilot fehlt,
  3 = Fehler
=====================================================================
#>
param([ValidateSet('Ein', 'Aus', '')][string]$Schalter = '')

$Root = 'C:\Fernwartung\PatchPilot'
$Option = Join-Path $Root 'Update-Option.ps1'
$Flag = Join-Path $Root 'Config\Funktionsupdates-Aus'
function Say([string]$Msg) { Write-Output ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg) }

$p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Say 'FEHLER: Bitte in der Clientverwaltung als "System" ausfuehren.'; exit 1 }
if (-not (Test-Path -LiteralPath $Option)) { Say 'FEHLER: Patch Pilot 0.10.4 oder neuer ist nicht installiert (Update-Option.ps1 fehlt).'; exit 2 }

if ($Schalter) {
    $action = 'FeatureOn'; if ($Schalter -eq 'Aus') { $action = 'FeatureOff' }
    $sysDir = 'System32'
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { $sysDir = 'Sysnative' }
    $ps = Join-Path $env:SystemRoot ($sysDir + '\WindowsPowerShell\v1.0\powershell.exe')
    & $ps -NoProfile -ExecutionPolicy Bypass -File $Option -Action $action
    if ($LASTEXITCODE -ne 0) { Say "FEHLER: Umschalten nicht moeglich (Code $LASTEXITCODE). Log: $Root\Logs"; exit 3 }
}
$state = 'freigegeben'; if (Test-Path -LiteralPath $Flag) { $state = 'aus' }
Say "Funktionsupdates auf diesem PC: $state"
exit 0
