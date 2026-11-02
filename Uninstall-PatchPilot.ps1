#requires -Version 5.1
<#
=====================================================================
Uninstall-PatchPilot  (Patch Pilot 0.10.4, Deinstallation)
=====================================================================
ZWECK
  Entfernt Patch Pilot vollstaendig und wiederholbar:
    1. Aufgaben PatchPilot-* beenden und loeschen
    2. laufende Skripte dieses Programms beenden
    3. Desktop-Verknuepfung entfernen (nur wenn sie unsere ist) und den
       Absendernamen der Windows-Hinweise (HKCU\Software\Classes\
       AppUserModelId\PatchPilot) bei allen gerade angemeldeten Benutzern
       entfernen. Bei nicht angemeldeten Benutzern bleibt dieser kleine,
       harmlose Eintrag im Profil.
    4. Programmdateien, Zustand und eigene Logs loeschen
    5. Programmordner entfernen, wenn nichts Fremdes darin liegt
  Fremde oder unbekannte Dateien werden NICHT geloescht, sondern gemeldet.
  Windows-Updates selbst und bereits installierte Updates bleiben unberuehrt.

AUFRUF
  Clientverwaltung (SYSTEM):   powershell.exe -ExecutionPolicy Bypass -File <Skript>
  Administrator:       Deinstall.bat im Programmordner (UAC-Abfrage)

VORAUSSETZUNGEN
  Windows 11, PowerShell 5.1, Administrator oder SYSTEM.

SICHERHEIT
  Nur ausfuehrbar als Administrator. Teilweise fehlgeschlagene Laeufe
  koennen jederzeit erneut gestartet werden.

PARAMETER
  -Root         Programmordner (Standard C:\Fernwartung\PatchPilot)
  -Interactive  Am Ende Abschlussmeldung mit OK zeigen (von Deinstall.bat gesetzt)

DATENSCHUTZ
  Bericht: <Elternordner von Root>\PatchPilot_Deinstallationsbericht_<Zeit>.txt
  (bleibt bewusst ausserhalb des Programmordners erhalten).

EXITCODES
  0 = vollstaendig entfernt
  2 = entfernt, aber fremde Dateien verbleiben im Programmordner
  3 = Fehler bei mindestens einem Schritt (erneut ausfuehren)
  1 = nicht als Administrator gestartet
=====================================================================
#>
[CmdletBinding()]
param(
    [string]$Root = 'C:\Fernwartung\PatchPilot',
    [switch]$Interactive
)

$ErrorActionPreference = 'Continue'
$Prefix = 'PatchPilot-'
$script:Errors = 0
$script:Foreign = New-Object System.Collections.Generic.List[string]
$script:Report = New-Object System.Collections.Generic.List[string]

function Say([string]$Msg) {
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg
    $script:Report.Add($line)
    Write-Host $line
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

# Wenn von Deinstall.bat gestartet: kurz warten, bis sich die .bat beendet hat (Dateisperre)
if ($Interactive) { Start-Sleep -Seconds 3 }
Say 'Deinstallation gestartet (Patch Pilot 0.10.4)'

# 1. Aufgaben entfernen
foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -eq '\' -and $_.TaskName -like "$Prefix*" })) {
    try {
        Disable-ScheduledTask -TaskPath '\' -TaskName $t.TaskName | Out-Null
        if ((Get-ScheduledTask -TaskPath '\' -TaskName $t.TaskName).State -eq 'Running') { Stop-ScheduledTask -TaskPath '\' -TaskName $t.TaskName }
        Unregister-ScheduledTask -TaskPath '\' -TaskName $t.TaskName -Confirm:$false
        Say "Aufgabe entfernt: $($t.TaskName)"
    } catch {
        $script:Errors++
        Say "FEHLER bei Aufgabe $($t.TaskName): $($_.Exception.Message)"
    }
}

# 2. Eigene Skriptprozesse beenden
foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue)) {
    if ($p.ProcessId -eq $PID) { continue }
    if ($p.CommandLine -and $p.CommandLine.IndexOf($Root, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop; Say "Prozess beendet: $($p.ProcessId)" }
        catch { $script:Errors++; Say "FEHLER: Prozess $($p.ProcessId) nicht beendbar: $($_.Exception.Message)" }
    }
}

# 3. Desktop-Verknuepfung (nur wenn unsere)
$link = Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'Windows Updates jetzt starten.lnk'
if (Test-Path -LiteralPath $link) {
    try {
        $sc = (New-Object -ComObject WScript.Shell).CreateShortcut($link)
        if ($sc.Arguments -like '*Update-User*') { Remove-Item -LiteralPath $link -Force; Say 'Desktop-Verknuepfung entfernt.' }
        else { Say 'Desktop-Verknuepfung gehoert nicht zu diesem Programm und bleibt.' }
    } catch { $script:Errors++; Say "FEHLER bei Verknuepfung: $($_.Exception.Message)" }
}

# 3b. Absendername der Windows-Hinweise (nur geladene Benutzerprofile)
foreach ($k in @(Get-ChildItem -LiteralPath 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like '*_Classes' })) {
    $key = 'Registry::HKEY_USERS\' + $k.PSChildName + '\AppUserModelId\PatchPilot'
    if (Test-Path -LiteralPath $key) {
        try { Remove-Item -LiteralPath $key -Recurse -Force; Say 'Absendername der Windows-Hinweise entfernt (ein Benutzerprofil).' }
        catch { $script:Errors++; Say "FEHLER beim Absendernamen: $($_.Exception.Message)" }
    }
}

# 3c. Von Patch Pilot gesperrte (in Windows ausgeblendete) Updates wieder einblenden,
#     damit nach der Deinstallation nichts dauerhaft versteckt bleibt.
$blk = Join-Path $Root 'Update-Blocklist.ps1'
if ((Test-Path -LiteralPath (Join-Path $Root 'State\hidden.json')) -and (Test-Path -LiteralPath $blk)) {
    try {
        function Write-Log([string]$Level, [string]$Msg) { Say "[$Level] $Msg" }
        . $blk
        $wuSession = New-Object -ComObject Microsoft.Update.Session
        $wuSession.ClientApplicationID = 'PatchPilot'
        Restore-UnblockedUpdates $wuSession 0 $true -All   # WSUS
        Restore-UnblockedUpdates $wuSession 2 $true -All   # Windows Update
        foreach ($e in @(Read-HiddenList)) { Say "WARNUNG: noch ausgeblendet (bitte mit dem Microsoft-Werkzeug wushowhide einblenden): $($e.Title) | ID $($e.Id)" }
    } catch {
        $script:Errors++
        Say ("FEHLER beim Einblenden gesperrter Updates: " + $_.Exception.Message)
    }
}

# 4. Dateien
$ownFiles = @('Update-*.ps1', 'Uninstall-PatchPilot*.ps1', 'Install-PatchPilot*.ps1', 'Notaus*.ps1', 'Version *', 'Deinstall.bat', 'Notaus.bat', 'Notaus-Aufheben.bat', 'Treiber-Ein.bat', 'Treiber-Aus.bat', 'Funktionsupdates-Ein.bat', 'Funktionsupdates-Aus.bat', 'Direktbezug-Microsoft.bat')
$self = $PSCommandPath
if (Test-Path -LiteralPath $Root) {
    foreach ($f in @(Get-ChildItem -LiteralPath $Root -Force -File -ErrorAction SilentlyContinue)) {
        $own = $false
        foreach ($pat in $ownFiles) { if ($f.Name -like $pat) { $own = $true } }
        if (-not $own) { $script:Foreign.Add($f.FullName); continue }
        if ($self -and ($f.FullName -ieq $self)) { continue }
        try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; Say "Datei entfernt: $($f.Name)" }
        catch { $script:Errors++; Say "FEHLER: $($f.Name) nicht loeschbar: $($_.Exception.Message)" }
    }
    $logDir = Join-Path $Root 'Logs'
    if (Test-Path -LiteralPath $logDir) {
        foreach ($f in @(Get-ChildItem -LiteralPath $logDir -Force -ErrorAction SilentlyContinue)) {
            if ($f.PSIsContainer -or ($f.Name -notlike 'Update*_*.log' -and $f.Name -notlike 'PatchPilot_*.log')) { $script:Foreign.Add($f.FullName); continue }
            try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop } catch { $script:Errors++; Say "FEHLER: Log $($f.Name): $($_.Exception.Message)" }
        }
    }
    $stateDir = Join-Path $Root 'State'
    if (Test-Path -LiteralPath $stateDir) {
        foreach ($f in @(Get-ChildItem -LiteralPath $stateDir -Force -ErrorAction SilentlyContinue)) {
            if ($f.PSIsContainer -or @('state.json', 'state.json.tmp', 'state.json.bad', 'failures.json', 'failures.json.tmp', 'failures.json.bad', 'failures_microsoft.json', 'failures_microsoft.json.tmp', 'failures_microsoft.json.bad', 'hidden.json', 'hidden.json.tmp') -notcontains $f.Name) { $script:Foreign.Add($f.FullName); continue }
            try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop } catch { $script:Errors++; Say "FEHLER: Zustand $($f.Name): $($_.Exception.Message)" }
        }
    }
    $cfgDir = Join-Path $Root 'Config'
    if (Test-Path -LiteralPath $cfgDir) {
        foreach ($f in @(Get-ChildItem -LiteralPath $cfgDir -Force -ErrorAction SilentlyContinue)) {
            if ($f.PSIsContainer -or @('Sperrliste.txt', 'Treiber-Aus', 'Funktionsupdates-Aus') -notcontains $f.Name) { $script:Foreign.Add($f.FullName); continue }
            try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop } catch { $script:Errors++; Say "FEHLER: Einstellung $($f.Name): $($_.Exception.Message)" }
        }
    }
    foreach ($d in @($logDir, $stateDir, $cfgDir)) {
        if ((Test-Path -LiteralPath $d) -and -not @(Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue).Count) {
            try { Remove-Item -LiteralPath $d -Force -ErrorAction Stop; Say "Ordner entfernt: $(Split-Path $d -Leaf)" } catch { $script:Errors++; Say "FEHLER: Ordner $d : $($_.Exception.Message)" }
        }
    }
    # Dieses Skript zuletzt
    if ($self -and (Test-Path -LiteralPath $self) -and $self.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase)) {
        try { Remove-Item -LiteralPath $self -Force -ErrorAction Stop; Say 'Deinstallationsskript entfernt.' }
        catch { $script:Errors++; Say "FEHLER: Deinstallationsskript nicht loeschbar: $($_.Exception.Message)" }
    }
    if (-not @(Get-ChildItem -LiteralPath $Root -Force -ErrorAction SilentlyContinue).Count) {
        try { Remove-Item -LiteralPath $Root -Force -ErrorAction Stop; Say 'Programmordner entfernt.' }
        catch { $script:Errors++; Say "FEHLER: Programmordner nicht loeschbar: $($_.Exception.Message)" }
    }
} else {
    Say 'Programmordner existiert nicht (mehr). Nichts zu loeschen.'
}

# 5. Ergebnis und Bericht
$code = 0
if ($script:Foreign.Count -gt 0) {
    $code = 2
    Say 'Fremde Dateien verbleiben (nicht geloescht):'
    foreach ($f in $script:Foreign) { Say "  $f" }
}
if ($script:Errors -gt 0) { $code = 3; Say "Es gab $($script:Errors) Fehler. Bitte Deinstallation erneut ausfuehren." }
if ($code -eq 0) { Say 'Deinstallation vollstaendig abgeschlossen.' }

$reportDir = Split-Path -Parent $Root
if (-not $reportDir -or -not (Test-Path -LiteralPath $reportDir)) { $reportDir = $env:ProgramData }
$reportFile = Join-Path $reportDir ('PatchPilot_Deinstallationsbericht_{0}.txt' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
try { Set-Content -LiteralPath $reportFile -Value $script:Report -Encoding UTF8; Write-Host "Bericht: $reportFile" } catch { Write-Host 'Bericht konnte nicht geschrieben werden.' }
switch ($code) {
    0       { Show-Done 'Deinstallation abgeschlossen. Patch Pilot ist entfernt.' }
    2       { Show-Done "Deinstallation abgeschlossen. Fremde Dateien sind im Programmordner geblieben.`n`nBericht: $reportFile" }
    default { Show-Done "Deinstallation mit Fehlern. Bitte erneut ausführen.`n`nBericht: $reportFile" $true }
}
exit $code
