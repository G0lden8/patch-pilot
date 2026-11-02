#requires -Version 5.1
<#
=====================================================================
Start-PatchPilot-Clientverwaltung_V0.10.4  (Patch Pilot 0.10.4, Updates aus der Clientverwaltung starten)
=====================================================================
ZWECK
  Startet einen Patch-Pilot-Updatelauf OHNE Abfrage, die der Benutzer
  bestaetigen muss. Das Skript startet nur die feste Aufgabe
  PatchPilot-Fernstart (vom Installer angelegt) und kehrt sofort zurueck.
  Den eigentlichen Lauf macht Patch Pilot selbst (Log im Programmordner).

WAS DER BENUTZER SIEHT (wie beim Desktop-Button, nur ohne Startabfrage)
  - Windows-Hinweis "Updates werden geladen und installiert"
  - Citrix-Hinweis (Fenster ohne Knopf, schliesst nach 30 Sekunden)
  - am Ende: Windows-Hinweis "abgeschlossen" oder Windows-Neustart-Hinweis
    (60 Sekunden Vorlauf)
  Keine Netzteil-Abfrage: Firmware im Akkubetrieb nur ab 50 % Akku,
  sonst automatisch beim naechsten Updatelauf.
  Danach gilt die Pause wie nach dem Desktop-Button (5 Tage 12 Std.).

EINSTELLUNGEN IN DER CLIENTVERWALTUNG
  Sprache PowerShell, Betriebssystem Windows, Architektur 64 Bit,
  Ausfuehren als SYSTEM.

SICHERHEIT
  Startet nur die vorhandene Aufgabe. Keine Downloads, keine Dateien,
  keine Aenderung an Einstellungen. Laeuft der Lauf schon, wird kein
  zweiter gestartet. Ist Notaus aktiv (Aufgabe deaktiviert), passiert nichts.

DATENSCHUTZ
  Ausgabe nur Status und Codes, keine Benutzernamen.

EXITCODES (sichtbar im Protokoll der Clientverwaltung)
  0 = Updatelauf gestartet
  1 = nicht als Administrator/SYSTEM gestartet
  2 = Patch Pilot nicht installiert (Aufgabe PatchPilot-Fernstart fehlt,
      Version 0.9.14 oder neuer noetig)
  3 = Updatelauf laeuft bereits, nichts gestartet
  4 = Start fehlgeschlagen
  5 = Notaus aktiv (Aufgabe deaktiviert), nichts gestartet
=====================================================================
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$TaskName = 'PatchPilot-Fernstart'

function Invoke-Start {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Output 'FEHLER: Bitte als SYSTEM bzw. Administrator ausfuehren (Clientverwaltung: "Ausfuehren als SYSTEM").'
        return 1
    }

    $task = Get-ScheduledTask -TaskPath '\' -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Output "FEHLER: Aufgabe $TaskName nicht gefunden. Patch Pilot 0.9.14 oder neuer installieren."
        return 2
    }
    if ($task.State -eq 'Disabled') {
        Write-Output 'Notaus ist aktiv (Aufgabe deaktiviert). Es wurde nichts gestartet.'
        return 5
    }
    # Laeuft schon ein Patch-Pilot-Lauf (z. B. Desktop-Button oder Freitag)? Dann keinen zweiten anstossen.
    $busy = @(Get-ScheduledTask -TaskPath '\' -ErrorAction SilentlyContinue | Where-Object {
        $_.TaskName -in 'PatchPilot-Fernstart', 'PatchPilot-Direct', 'PatchPilot-Manual', 'PatchPilot-Manual-Shutdown', 'PatchPilot-Friday', 'PatchPilot-Boot', 'PatchPilot-Remind', 'PatchPilot-Preload' -and $_.State -eq 'Running' })
    if ($busy.Count -gt 0) {
        Write-Output ('Ein Updatelauf laeuft bereits (' + (($busy | ForEach-Object { $_.TaskName }) -join ', ') + '). Es wurde nichts gestartet.')
        return 3
    }

    try {
        Start-ScheduledTask -TaskPath '\' -TaskName $TaskName
    } catch {
        Write-Output ('FEHLER: Start nicht moeglich: ' + $_.Exception.Message)
        return 4
    }
    Write-Output 'Updatelauf gestartet (ohne Abfrage). Ergebnis: Log unter C:\Fernwartung\PatchPilot\Logs.'
    return 0
}

try {
    $code = Invoke-Start
} catch {
    Write-Output ('FEHLER: Unerwartet: ' + $_.Exception.Message)
    $code = 4
}
exit $code
