#requires -Version 5.1
<#
=====================================================================
Update-Option  (Patch Pilot 0.10.4, Schalter fuer Administratoren)
=====================================================================
ZWECK
  Hinter den Startdateien im Programmordner (nur als Administrator):
    Treiber-Ein.bat            -Action DriversOn   Treiber-Zusatz einschalten
    Treiber-Aus.bat            -Action DriversOff  Treiber-Zusatz ausschalten
    Funktionsupdates-Ein.bat   -Action FeatureOn   Funktionsupdates freigeben (Standard)
    Funktionsupdates-Aus.bat   -Action FeatureOff  Funktionsupdates ueberspringen
    Direktbezug-Microsoft.bat  -Action Direct      alle wichtigen Updates jetzt
                                                   direkt bei Microsoft holen
  Treiber-Zusatz: Schalter ist die Datei Config\Treiber-Aus (vorhanden =
  aus). Ohne Datei ist er an (Standard). Der Installer laesst die Datei
  unberuehrt, die Einstellung bleibt also bei Updates erhalten.
  Direktbezug: startet die Aufgabe PatchPilot-Direct. Ablauf wie beim
  Start durch die Clientverwaltung (keine Abfrage, Hinweise, Neustart bei Bedarf).

SICHERHEIT
  Nur als Administrator. Aendert nur die Schalterdatei bzw. startet eine
  vorhandene Aufgabe. Ordner Config: nur SYSTEM und Administratoren.

PARAMETER
  -Action       DriversOn | DriversOff | Direct
  -Root         Programmordner (Standard C:\Fernwartung\PatchPilot)
  -Interactive  Abschlussmeldung mit OK anzeigen (Start ueber die .bat)

EXITCODES
  0 = erledigt, 1 = nicht als Administrator, 2 = Aufgabe fehlt,
  3 = Fehler, 4 = Updatelauf laeuft bereits, 5 = Notaus aktiv
=====================================================================
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('DriversOn','DriversOff','FeatureOn','FeatureOff','Direct')][string]$Action,
    [string]$Root = 'C:\Fernwartung\PatchPilot',
    [switch]$Interactive
)

$ErrorActionPreference = 'Stop'
$LogDir  = Join-Path $Root 'Logs'
$LogFile = Join-Path $LogDir ('PatchPilot_{0}.log' -f (Get-Date -Format 'yyyy-MM'))
$Flag    = Join-Path $Root 'Config\Treiber-Aus'
$FeatureFlag = Join-Path $Root 'Config\Funktionsupdates-Aus'
$RunTasks = @('PatchPilot-Direct', 'PatchPilot-Fernstart', 'PatchPilot-Manual', 'PatchPilot-Manual-Shutdown', 'PatchPilot-Friday', 'PatchPilot-Boot', 'PatchPilot-Remind', 'PatchPilot-Preload')

function Say([string]$Msg) {
    $line = '{0} [INFO] [Option] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg
    Write-Host $line
    if (Test-Path -LiteralPath $LogDir) {
        for ($try = 1; $try -le 10; $try++) {
            try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop; break } catch { Start-Sleep -Milliseconds (Get-Random -Minimum 50 -Maximum 300) }
        }
    }
}

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

function Invoke-Option {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'FEHLER: Nur als Administrator ausfuehrbar.'
        Show-Done 'Nur als Administrator ausführbar.' $true
        return 1
    }
    switch ($Action) {
        'DriversOn' {
            if (Test-Path -LiteralPath $Flag) { Remove-Item -LiteralPath $Flag -Force }
            Say 'Treiber-Zusatz eingeschaltet (durch Administrator).'
            Show-Done 'Treiber-Zusatz ist eingeschaltet. Wichtige Treiber und Firmware werden ab dem nächsten Updatelauf zusätzlich direkt bei Microsoft gesucht.'
            return 0
        }
        'DriversOff' {
            $dir = Split-Path -Parent $Flag
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            [IO.File]::WriteAllText($Flag, ('Treiber-Zusatz ausgeschaltet am ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')), [Text.Encoding]::ASCII)
            Say 'Treiber-Zusatz ausgeschaltet (durch Administrator).'
            Show-Done 'Treiber-Zusatz ist ausgeschaltet. Es werden nur noch die WSUS-Updates installiert.'
            return 0
        }
        'FeatureOn' {
            if (Test-Path -LiteralPath $FeatureFlag) { Remove-Item -LiteralPath $FeatureFlag -Force }
            Say 'Funktionsupdates freigegeben (durch Administrator).'
            Show-Done 'Funktionsupdates sind freigegeben. Neue Windows-Versionen werden wieder mitinstalliert, wenn sie angeboten werden.'
            return 0
        }
        'FeatureOff' {
            $dir = Split-Path -Parent $FeatureFlag
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            [IO.File]::WriteAllText($FeatureFlag, ('Funktionsupdates ausgeschaltet am ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')), [Text.Encoding]::ASCII)
            Say 'Funktionsupdates ausgeschaltet (durch Administrator).'
            Show-Done 'Funktionsupdates sind ausgeschaltet. Neue Windows-Versionen werden übersprungen, alle anderen Updates laufen normal weiter.'
            return 0
        }
        'Direct' {
            $task = Get-ScheduledTask -TaskPath '\' -TaskName 'PatchPilot-Direct' -ErrorAction SilentlyContinue
            if (-not $task) { Show-Done 'Aufgabe PatchPilot-Direct fehlt. Bitte den Installer erneut ausführen.' $true; return 2 }
            if ($task.State -eq 'Disabled') { Say 'Direktbezug nicht gestartet: Notaus aktiv.'; Show-Done 'Notaus ist aktiv. Es wurde nichts gestartet.' $true; return 5 }
            $busy = @(Get-ScheduledTask -TaskPath '\' -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -in $RunTasks -and $_.State -eq 'Running' })
            if ($busy.Count -gt 0) { Say 'Direktbezug nicht gestartet: ein Updatelauf laeuft bereits.'; Show-Done 'Ein Updatelauf läuft bereits. Bitte später erneut versuchen.' $true; return 4 }
            Start-ScheduledTask -TaskPath '\' -TaskName 'PatchPilot-Direct'
            Say 'Direktbezug bei Microsoft gestartet (durch Administrator).'
            Show-Done 'Direktbezug bei Microsoft gestartet. Alle wichtigen Updates werden jetzt direkt bei Microsoft geladen und installiert (Sperrliste wird beachtet). Ergebnis: Ordner Logs.'
            return 0
        }
    }
    return 3
}

$code = 3
try { $code = Invoke-Option }
catch {
    Write-Host ('FEHLER: ' + $_.Exception.Message)
    Say ('FEHLER (' + $Action + '): ' + $_.Exception.Message)
    Show-Done 'Fehler. Details: Ordner Logs im Programmordner.' $true
    $code = 3
}
exit $code
