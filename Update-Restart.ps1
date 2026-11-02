#requires -Version 5.1
<#
=====================================================================
Update-Restart  (Patch Pilot 0.10.4, Neustart nur, wenn Windows ihn verlangt)
=====================================================================
ZWECK
  Prueft, ob Windows nach Updates einen Neustart verlangt. Nur dann wird
  der PC mit 60 Sekunden Vorlauf neu gestartet. Der Hinweis erscheint
  ueber den Windows-eigenen Mechanismus (shutdown.exe):
  "Neustart in 60 Sekunden, um das Update abzuschliessen."

ABLAUF
  1. Admin-Pruefung, Schutz gegen Parallelstart (gleicher Mutex wie die anderen Module)
  2. Neustartbedarf lesen (Windows Update Agent, Microsoft.Update.SystemInfo)
  3. Kein Bedarf -> nichts tun (Exitcode 0)
  4. Bedarf -> shutdown.exe /r /f /t 60 /c "<Text>" (ein einziger Aufruf)
     Laeuft bereits ein geplanter Neustart (Windows-Fehler 1190), wird kein
     zweiter Mechanismus aufgebaut.

VORAUSSETZUNGEN
  Windows 11, PowerShell 5.1, Start als Administrator/SYSTEM.

SICHERHEIT
  Keine Zustimmung, keine Verschiebemoeglichkeit, nur ein Hinweis, keine
  mehrfachen Dialoge. /f schliesst lokale Programme ohne Speichern nach den
  60 Sekunden. Keine Citrix-Aktion (Citrix wird vorher getrennt, nie abgemeldet).
  Bei Notfall: "shutdown /a" bricht einen geplanten Neustart ab.

PARAMETER
  -Root            Hauptordner (Standard C:\Fernwartung\PatchPilot)
  -DelaySeconds    Vorlaufzeit in Sekunden (Standard 60)
  -DryRun          Nur pruefen und loggen, NICHT neu starten (zum Testen)
  -ForceTest       NUR TEST: Neustart ausloesen, auch wenn Windows keinen verlangt
                   (nur ueber Test-Neustart.bat, nie ueber Aufgaben)

DATENSCHUTZ
  Geloggt werden nur Neustartstatus und Fehlercodes.

EXITCODES
  0  = kein Neustart noetig, nichts getan
  20 = Neustart wurde geplant (oder war bereits geplant)
  21 = DryRun: Neustart waere noetig gewesen
  1  = nicht als Administrator gestartet
  3  = shutdown.exe fehlgeschlagen
  5  = laeuft bereits (zweite Instanz)
=====================================================================
#>
[CmdletBinding()]
param(
    [string]$Root = 'C:\Fernwartung\PatchPilot',
    [ValidateRange(10, 600)][int]$DelaySeconds = 60,
    [switch]$DryRun,
    [switch]$ForceTest
)

$ErrorActionPreference = 'Stop'
$LogDir  = Join-Path $Root 'Logs'
$LogFile = Join-Path $LogDir ('PatchPilot_{0}.log' -f (Get-Date -Format 'yyyy-MM'))
$LogTag = 'Restart'
$Message = 'Neustart in 60 Sekunden, um das Update abzuschließen.'
if ($DelaySeconds -ne 60) { $Message = "Neustart in $DelaySeconds Sekunden, um das Update abzuschließen." }

function Write-Log([string]$Level, [string]$Msg) {
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $LogTag, $Msg
    # Eine gemeinsame Monatsdatei fuer alle Teile. Schreiben andere gerade, kurz warten und erneut versuchen.
    for ($try = 1; $try -le 10; $try++) {
        try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop; break } catch { Start-Sleep -Milliseconds (Get-Random -Minimum 50 -Maximum 300) }
    }
    Write-Host $line
}

function Invoke-Main {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'FEHLER: Bitte als Administrator starten.'
        return 1
    }
    if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    Write-Log 'INFO' 'Update-Restart gestartet (Patch Pilot 0.10.4)'

    $needed = $false
    try { $needed = [bool](New-Object -ComObject Microsoft.Update.SystemInfo).RebootRequired }
    catch { Write-Log 'WARN' ("Neustartstatus nicht lesbar: 0x{0:X8}. Kein Neustart ausgeloest." -f $_.Exception.HResult); return 0 }
    Write-Log 'INFO' "Neustart erforderlich (Windows-Status): $needed"
    if ($ForceTest) { $needed = $true; Write-Log 'WARN' 'TESTMODUS: Neustart wird erzwungen, obwohl Windows keinen verlangt.' }

    if (-not $needed) {
        Write-Log 'INFO' 'Kein Neustart noetig. Ende.'
        return 0
    }
    if ($DryRun) {
        Write-Log 'INFO' 'DryRun: Neustart waere jetzt geplant worden. Es wird NICHT neu gestartet.'
        return 21
    }

    $exe = Join-Path $env:SystemRoot 'System32\shutdown.exe'
    Write-Log 'INFO' "Phase Neustart: Aktion shutdown /r /f /t $DelaySeconds"
    & $exe /r /f /t $DelaySeconds /c $Message /d p:2:17
    $rc = $LASTEXITCODE
    if ($rc -eq 0) {
        Write-Log 'INFO' 'Neustart geplant. Abbruch nur durch Administrator mit: shutdown /a'
        return 20
    }
    if ($rc -eq 1190) {
        Write-Log 'INFO' 'Es ist bereits ein Neustart geplant. Kein zweiter Mechanismus.'
        return 20
    }
    Write-Log 'ERROR' "shutdown.exe fehlgeschlagen, Exitcode $rc. Naechster Schritt: spaeterer Lauf"
    return 3
}

$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Global\PatchPilot_UpdateCore', [ref]$created)
if (-not $created) {
    Write-Host 'Ein anderes Update-Modul laeuft bereits. Abbruch.'
    exit 5
}
$code = 0
try { $code = Invoke-Main }
catch { Write-Host ("Unerwarteter Fehler: " + $_.Exception.Message); $code = 3 }
finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
exit $code
