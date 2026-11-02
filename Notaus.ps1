#requires -Version 5.1
<#
=====================================================================
Notaus  (Patch Pilot 0.10.4, Notbremse fuer Patch Pilot)
=====================================================================
ZWECK
  Stoppt die Steuerung sofort, wenn sie haengt oder Arbeiten verhindert:
    1. alle Aufgaben PatchPilot-* deaktivieren und laufende Aufgaben beenden
    2. alle laufenden Skripte dieses Programms beenden (nur PowerShell-
       Prozesse, deren Befehlszeile den Programmordner enthaelt)
    3. einen geplanten Neustart/Shutdown abbrechen (shutdown /a)
    4. vorgemerktes "PC ausschalten" im Zustand loeschen
  Es werden KEINE Windows-Dienste und KEINE Citrix-Prozesse beendet.
  Es gibt keine Sperren; nach einem Neustart ist der PC ohnehin frei nutzbar.

WIEDER AKTIVIEREN
  Notaus-Aufheben.bat (ruft dieses Skript mit -Aufheben auf): aktiviert alle
  Aufgaben PatchPilot-* wieder. Keine Neuinstallation noetig.

VORAUSSETZUNGEN
  Windows 11, PowerShell 5.1, Administrator (Start ueber Notaus.bat mit UAC).

SICHERHEIT
  Nur ausfuehrbar als Administrator. Keine Aenderung an WSUS/GPO/Updates.

PARAMETER
  -Root         Programmordner (Standard C:\Fernwartung\PatchPilot)
  -Aufheben     Notaus aufheben: Aufgaben wieder aktivieren (stoppt nichts)
  -Interactive  Am Ende Abschlussmeldung mit OK zeigen (von Notaus.bat gesetzt)

DATENSCHUTZ
  Log: <Root>\Logs\PatchPilot_<Jahr-Monat>.log (eine Datei pro Monat), nur Aktionen und Codes.

EXITCODES
  0 = erledigt
  1 = nicht als Administrator gestartet
  3 = erledigt, aber mindestens ein Schritt ist fehlgeschlagen
=====================================================================
#>
[CmdletBinding()]
param(
    [string]$Root = 'C:\Fernwartung\PatchPilot',
    [switch]$Aufheben,
    [switch]$Interactive
)

$ErrorActionPreference = 'Continue'
$Prefix  = 'PatchPilot-'
$LogDir  = Join-Path $Root 'Logs'
$LogFile = Join-Path $LogDir ('PatchPilot_{0}.log' -f (Get-Date -Format 'yyyy-MM'))
$script:Errors = 0

function Say([string]$Msg) {
    $line = '{0} [Notaus] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg
    Write-Host $line
    if (Test-Path -LiteralPath $LogDir) {
        for ($try = 1; $try -le 10; $try++) {
            try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop; break } catch { Start-Sleep -Milliseconds (Get-Random -Minimum 50 -Maximum 300) }
        }
    }
}

# Abschlussmeldung (nur beim Start ueber die .bat): kleines Fenster mit OK, danach schliesst sich alles von selbst.
function Show-Done([string]$Text, [bool]$IsError = $false) {
    if (-not $Interactive) { return }
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $owner = New-Object System.Windows.Forms.Form
        $owner.TopMost = $true
        $icon = 'Information'; if ($IsError) { $icon = 'Warning' }
        [void][System.Windows.Forms.MessageBox]::Show($owner, $Text, 'Patch Pilot', 'OK', $icon)
        $owner.Dispose()
    } catch { Write-Host ('Meldefenster nicht anzeigbar: ' + $_.Exception.Message) }
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'FEHLER: Nur als Administrator ausfuehrbar.'
    Show-Done 'Nur als Administrator ausführbar.' $true
    exit 1
}

if ($Aufheben) {
    Say 'Notaus aufheben gestartet (Patch Pilot 0.10.4)'
    foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -eq '\' -and $_.TaskName -like "$Prefix*" })) {
        try { Enable-ScheduledTask -TaskPath '\' -TaskName $t.TaskName | Out-Null; Say "Aufgabe aktiviert: $($t.TaskName)" }
        catch { $script:Errors++; Say "FEHLER bei Aufgabe $($t.TaskName): $($_.Exception.Message)" }
    }
    Say 'Fertig. Die Steuerung ist wieder aktiv.'
    if ($script:Errors -gt 0) { Show-Done "Notaus aufheben mit $($script:Errors) Fehler(n). Bitte erneut ausführen. Details: Ordner Logs im Programmordner." $true; exit 3 }
    Show-Done 'Notaus aufgehoben. Patch Pilot ist wieder aktiv.'
    exit 0
}

Say 'Notaus gestartet (Patch Pilot 0.10.4)'

# 1. Aufgaben deaktivieren und stoppen
foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -eq '\' -and $_.TaskName -like "$Prefix*" })) {
    try {
        Disable-ScheduledTask -TaskPath '\' -TaskName $t.TaskName | Out-Null
        if ((Get-ScheduledTask -TaskPath '\' -TaskName $t.TaskName).State -eq 'Running') {
            Stop-ScheduledTask -TaskPath '\' -TaskName $t.TaskName
        }
        Say "Aufgabe deaktiviert: $($t.TaskName)"
    } catch {
        $script:Errors++
        Say "FEHLER bei Aufgabe $($t.TaskName): $($_.Exception.Message)"
    }
}

# 2. Eigene Skriptprozesse beenden
$killed = 0
foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue)) {
    if ($p.ProcessId -eq $PID) { continue }
    if ($p.CommandLine -and $p.CommandLine.IndexOf($Root, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop; $killed++ }
        catch { $script:Errors++; Say "FEHLER: Prozess $($p.ProcessId) nicht beendbar: $($_.Exception.Message)" }
    }
}
Say "Beendete Skriptprozesse: $killed"

# 3. Geplanten Neustart/Shutdown abbrechen
& (Join-Path $env:SystemRoot 'System32\shutdown.exe') /a 2>&1 | Out-Null
$sa = $LASTEXITCODE
$saText = switch ($sa) { 0 { 'geplanter Neustart/Shutdown abgebrochen' } 1116 { 'es war nichts geplant' } default { 'unbekannt' } }
Say "shutdown /a Exitcode: $sa = $saText"

# 4. Vorgemerktes Ausschalten loeschen
$stateFile = Join-Path (Join-Path $Root 'State') 'state.json'
if (Test-Path -LiteralPath $stateFile) {
    try {
        $s = Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($n in @('ShutdownPending', 'ShutdownAfter')) {
            if ($s.PSObject.Properties[$n]) { $s.$n = $false }
        }
        [IO.File]::WriteAllText($stateFile, ($s | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
        Say 'Vorgemerktes Ausschalten geloescht.'
    } catch {
        $script:Errors++
        Say "FEHLER: Zustandsdatei nicht aenderbar: $($_.Exception.Message)"
    }
}

Say 'Fertig. Aufgaben bleiben deaktiviert. Wieder aktivieren: Notaus-Aufheben.bat.'
if ($script:Errors -gt 0) { Show-Done "Notaus mit $($script:Errors) Fehler(n). Bitte erneut ausführen. Details: Ordner Logs im Programmordner." $true; exit 3 }
Show-Done "Notaus ausgeführt. Patch Pilot ist angehalten.`n`nWieder aktivieren: Notaus-Aufheben.bat im Programmordner." 
exit 0
