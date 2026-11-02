#requires -Version 5.1
<#
=====================================================================
Install-PatchPilot  (Patch Pilot 0.10.4, Installation, wiederholbar)
=====================================================================
ZWECK
  Installiert Patch Pilot lokal (z. B. per Clientverwaltung als
  SYSTEM). Mehrfaches Ausfuehren erzeugt keine doppelten Aufgaben.
  Bis V0.9.11 hiess das Programm "Windows-Updates" (Ordner
  C:\Fernwartung\Windows_Updates, Aufgaben WUCtl-*). Der Installer zieht
  eine solche Installation automatisch um (siehe UMZUG).
  Ab 0.9.13 gibt es nur noch EINE Versionsnummer fuer das ganze Programm:
  Dateien heissen ohne Nummer (Update-Run.ps1 ...), im Programmordner
  zeigt eine leere Datei "Version <Nummer>" (z. B. "Version 0.9.14") den Stand.

ABLAUF
  1. Administrator pruefen, Zeiten pruefen, Paketdateien pruefen.
     Liegt im Zielordner schon etwas, das nicht von uns stammt: Abbruch.
  2. Programmordner mit Logs und State anlegen, Rechte setzen:
     SYSTEM und Administratoren Vollzugriff, Benutzer nur lesen/ausfuehren
     (State: nur SYSTEM und Administratoren)
  3. Dateien kopieren (Internetsperre aufheben), veraltete Versionen
     eigener Dateien entfernen
  4. Deinstall.bat, Notaus.bat, Notaus-Aufheben.bat, Treiber-Ein.bat, Treiber-Aus.bat,
     Funktionsupdates-Ein.bat, Funktionsupdates-Aus.bat
     und Direktbezug-Microsoft.bat schreiben (immer aktuell). Ordner Config (nur
     SYSTEM/Administratoren) mit Sperrliste.txt anlegen, falls keine vorhanden ist.
     Treiber-Zusatz-Einstellung (Config\Treiber-Aus) bleibt unveraendert.
     (fordern per UAC Administratorrechte an)
  5. Aufgaben anlegen (alle mit Namen PatchPilot-*):
       PatchPilot-Preload          Donnerstag, nur Download (SYSTEM)
       PatchPilot-Friday           Freitag zur eingestellten Stunde (SYSTEM)
       PatchPilot-Remind           einmaliger Zeitpunkt, von der Steuerung gesetzt
       PatchPilot-Boot             PC-Start und Anmeldung (SYSTEM)
       PatchPilot-Manual           Desktop-Button, durch Benutzer startbar
       PatchPilot-Manual-Shutdown  wie Manual, danach PC ausschalten
       PatchPilot-Fernstart        wie Manual, aber ohne Abfrage; Start nur durch
                                   Clientverwaltung/Administrator (Skript Start-PatchPilot-Clientverwaltung_V<Nummer>.ps1)
       PatchPilot-Direct           wie Fernstart, aber alle wichtigen Updates direkt bei
                                   Microsoft (Direktbezug-Microsoft.bat, nur Administrator)
       PatchPilot-User-ErrNoOffer  IT-Hinweis: WSUS bietet seit 45 Tagen nichts an
       PatchPilot-User-Ask1/Ask2/Notice/Disconnect/Power  Dialoge/Citrix/Netzteil im Benutzer-
                              konto (nur von SYSTEM startbar)
       PatchPilot-User-Guard       ab 0.10.4: Hinweis "Citrix bitte nicht starten" waehrend
                              der Installation (immer im Vordergrund, nur von SYSTEM startbar)
       PatchPilot-User-Workspace   ab 0.10.4: Citrix Workspace-App wieder starten, wenn
                              nach der Installation kein Neustart folgt
       PatchPilot-User-ErrNet/ErrFinal   Fenster (Update-Notify): Netz/VPN-Fehler am Freitag,
                              IT-Hinweis
       PatchPilot-User-Done/ErrPartial   ab 0.10.4 Fenster mit OK (Abschluss des manuellen
                              Laufs, bleibt bis OK stehen, hoechstens 4 Stunden)
       PatchPilot-User-Running/ErrManNet/ErrManGen   Windows-Hinweise zum
                              manuellen Lauf (Update-Notify; Running bleibt stehen, bis ein
                              anderer ihn ersetzt)
       Nicht mehr benoetigte Aufgaben frueherer Versionen (z. B. Started,
       PhaseDownload, PhaseInstall, DoneReboot, ErrGeneric) werden entfernt.
  6. Verknuepfung "Windows Updates jetzt starten" auf dem oeffentlichen
     Desktop anlegen

UMZUG (nur wenn die alte Installation gefunden wird)
  a. Laeuft gerade eine alte Aufgabe WUCtl-*: Abbruch (Code 3), damit keine
     laufende Installation unterbrochen wird. Spaeter erneut ausfuehren.
  b. Alte Aufgaben WUCtl-* und das alte Desktop-Symbol entfernen.
  c. Logs und State in den neuen Ordner verschieben (Verlauf, laufende
     Woche, Pausen und Fehltage bleiben erhalten). Logdateien werden
     umbenannt: WindowsUpdates_* -> PatchPilot_*.
  d. Eigene alte Dateien loeschen. Bleibt danach nichts Fremdes uebrig,
     wird der alte Ordner geloescht, sonst bleibt er (WARN im Log).

VORAUSSETZUNGEN
  Windows 11, PowerShell 5.1, Administrator oder SYSTEM. Das Paket
  (alle Dateien dieses Ordners) liegt im selben Ordner wie dieses Skript.
  Hinweis: Erzwingt eine Gruppenrichtlinie "AllSigned" oder "Restricted",
  laufen unsignierte Skripte nicht. Das wird im Log gemeldet.

SICHERHEIT
  Keine Aenderung an WSUS, Gruppenrichtlinien oder Updatequelle.
  Nur die Aufgabe PatchPilot-Manual und PatchPilot-Manual-Shutdown duerfen von
  normalen Benutzern gestartet werden, nichts sonst. Aendern/Loeschen nur
  durch Administratoren.

PARAMETER
  -Root         Programmordner (Standard C:\Fernwartung\PatchPilot)
  -PreloadTime  Donnerstag-Uhrzeit fuer den Download (Standard 12:00)
  -FridayTime   Freitag-Startzeit, volle Stunde (Standard 06:00)
  -SourceDir    Ordner mit den Paketdateien (Standard: Ordner dieses Skripts)

DATENSCHUTZ
  Log: <Root>\Logs\PatchPilot_<Jahr-Monat>.log (eine Datei pro Monat), nur Aktionen und Codes.

EXITCODES
  0 = installiert
  1 = nicht als Administrator gestartet
  2 = Paketdateien oder Zeitangaben ungueltig
  3 = Fehler bei der Installation (erneut ausfuehren)
=====================================================================
#>
[CmdletBinding()]
param(
    [string]$Root = 'C:\Fernwartung\PatchPilot',
    [string]$PreloadTime = '12:00',
    [string]$FridayTime = '06:00',
    [string]$SourceDir = ''
)

$ErrorActionPreference = 'Stop'
$Ver = '0.10.4'
$Prefix = 'PatchPilot-'
$PsExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$Payload = @(
    'Update-Run.ps1', 'Update-Notify.ps1', 'Update-Core.ps1', 'Update-Install.ps1',
    'Update-Restart.ps1', 'Update-User.ps1', 'Update-Settings.ps1', 'Update-Popup.ps1', 'Update-Power.ps1',
    'Uninstall-PatchPilot.ps1', 'Notaus.ps1',
    'Update-Microsoft.ps1', 'Update-Blocklist.ps1', 'Update-Option.ps1'
)
$LogDir = Join-Path $Root 'Logs'
$LogFile = Join-Path $LogDir ('PatchPilot_{0}.log' -f (Get-Date -Format 'yyyy-MM'))
$LogTag = 'Installer'
# Alte Installation (bis V0.9.11)
$OldRoot   = Join-Path (Split-Path -Parent $Root) 'Windows_Updates'
$OldPrefix = 'WUCtl-'
$OldLink   = 'Windows-Updates jetzt starten.lnk'

function Write-Log([string]$Level, [string]$Msg) {
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $LogTag, $Msg
    if (Test-Path -LiteralPath $LogDir) {
        for ($try = 1; $try -le 10; $try++) {
            try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop; break } catch { Start-Sleep -Milliseconds (Get-Random -Minimum 50 -Maximum 300) }
        }
    }
    Write-Host $line
}

function Get-DaclKey([string]$Sddl) {
    $sd = New-Object Security.AccessControl.RawSecurityDescriptor($Sddl)
    return (@($sd.DiscretionaryAcl | ForEach-Object { $_.SecurityIdentifier.Value + ':' + [int]$_.AceType + ':' + [int64]$_.AccessMask + ':' + [int]$_.AceFlags } | Sort-Object) -join ',')
}

function Set-Folder-Acl([string]$Path, [bool]$UsersRead) {
    $aclArgs = @($Path, '/inheritance:r', '/grant:r', '*S-1-5-18:(OI)(CI)F', '/grant:r', '*S-1-5-32-544:(OI)(CI)F')
    if ($UsersRead) { $aclArgs += @('/grant:r', '*S-1-5-32-545:(OI)(CI)RX') }
    & icacls.exe @aclArgs | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls fehlgeschlagen fuer $Path (Code $LASTEXITCODE)" }
    # Ab 0.10.2: alle anderen Rechte-Eintraege entfernen (icacls /grant:r ersetzt nur die genannten Konten,
    # fremde Eintraege, z. B. von einem frueheren Werkzeug, blieben sonst stehen).
    $allowed = @('S-1-5-18', 'S-1-5-32-544'); if ($UsersRead) { $allowed += 'S-1-5-32-545' }
    $acl = Get-Acl -LiteralPath $Path
    foreach ($r in @($acl.Access | Where-Object { -not $_.IsInherited })) {
        $sid = $null
        try { $sid = $r.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { $sid = [string]$r.IdentityReference }
        if ($allowed -contains $sid) { continue }
        & icacls.exe $Path /remove:g ('*' + $sid) | Out-Null
        & icacls.exe $Path /remove:d ('*' + $sid) | Out-Null
        Write-Log 'WARN' ("Fremdes Recht entfernt: {0}" -f (Split-Path $Path -Leaf))
    }
    # Dateien und Unterordner: eigene Sonderrechte zuruecksetzen, nur noch vom Ordner erben
    if (@(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue).Count -gt 0) {
        & icacls.exe (Join-Path $Path '*') /reset /T /C /Q | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Log 'WARN' ("Rechte einzelner Dateien nicht zuruecksetzbar: {0} (Code {1})" -f (Split-Path $Path -Leaf), $LASTEXITCODE) }
    }
}

function Write-Bat([string]$Path, [string]$Title, [string]$ScriptPattern, [string]$ExtraArgs = '') {
    $lines = @(
        '@echo off',
        "rem $Title - nur als Administrator. Die UAC-Abfrage erscheint automatisch.",
        'fltmc >nul 2>&1',
        'if errorlevel 1 (',
        '  echo Administratorrechte erforderlich. Die UAC-Abfrage wird geoeffnet...',
        '  powershell.exe -NoProfile -Command "Start-Process -FilePath ''%~f0'' -Verb RunAs"',
        '  exit /b',
        ')',
        'set "SCRIPT="',
        ('for %%F in ("%~dp0{0}") do set "SCRIPT=%%~fF"' -f $ScriptPattern),
        'if not defined SCRIPT (',
        '  powershell.exe -NoProfile -Command "Add-Type -AssemblyName System.Windows.Forms; $f=New-Object System.Windows.Forms.Form; $f.TopMost=$true; [void][System.Windows.Forms.MessageBox]::Show($f,''Skript nicht gefunden. Bitte den Installer erneut ausfuehren.'',''Patch Pilot'',''OK'',''Warning'')"',
        '  exit /b 2',
        ')',
        ('start "" powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "%SCRIPT%" {0}-Interactive' -f $ExtraArgs),
        'exit /b 0'
    )
    [IO.File]::WriteAllText($Path, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
    Write-Log 'INFO' "Geschrieben: $(Split-Path $Path -Leaf)"
}

function Register-Ctl([string]$Name, [string]$Script, [string]$ArgText, $Principal, $Triggers, [bool]$UserStartable, [int]$Hours) {
    $ws = ''
    # Benutzer-Aufgaben ohne sichtbares Konsolenfenster im Vordergrund (Dateinamen ohne Versionsnummer seit 0.9.13)
    if ($Script -like 'Update-User*.ps1' -or $Script -like 'Update-Notify*.ps1') { $ws = '-WindowStyle Minimized ' }
    $argLine = ('-NoProfile {0}-ExecutionPolicy RemoteSigned -File "{1}" {2}' -f $ws, (Join-Path $Root $Script), $ArgText).Trim()
    $action = New-ScheduledTaskAction -Execute $PsExe -Argument $argLine -WorkingDirectory $Root
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours $Hours) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $def = @{ Action = $action; Principal = $Principal; Settings = $settings; Description = "Patch Pilot $Ver" }
    if ($Triggers) { $def.Trigger = $Triggers }
    Register-ScheduledTask -TaskName $Name -TaskPath '\' -InputObject (New-ScheduledTask @def) -Force | Out-Null

    if ($UserStartable) { $sddl = 'O:BAG:BAD:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;FRFX;;;BU)' }
    else { $sddl = 'O:BAG:BAD:P(A;;FA;;;SY)(A;;FA;;;BA)' }
    $svc = New-Object -ComObject Schedule.Service
    $svc.Connect()
    $task = $svc.GetFolder('\').GetTask($Name)
    $task.SetSecurityDescriptor($sddl, 0x10)
    if ((Get-DaclKey $task.GetSecurityDescriptor(4)) -cne (Get-DaclKey $sddl)) { throw "Aufgabenrechte fuer $Name nicht wie erwartet" }
    Write-Log 'INFO' "Aufgabe angelegt: $Name (durch Benutzer startbar: $UserStartable)"
}

# Liegt im Zielordner schon etwas, das nicht von Patch Pilot stammt? (z. B. altes Fremdprogramm gleichen Namens)
# Erlaubt sind nur unsere Ordner Logs/State und unsere Dateinamen.
function Test-ForeignRoot {
    if (-not (Test-Path -LiteralPath $Root)) { return $false }
    $ours = @('Logs', 'State', 'Config', 'Version *', 'Update-*.ps1', 'Install-PatchPilot*.ps1', 'Uninstall-PatchPilot*.ps1', 'Notaus*.ps1', 'Deinstall.bat', 'Notaus.bat', 'Notaus-Aufheben.bat', 'Treiber-Ein.bat', 'Treiber-Aus.bat', 'Funktionsupdates-Ein.bat', 'Funktionsupdates-Aus.bat', 'Direktbezug-Microsoft.bat')
    foreach ($i in @(Get-ChildItem -LiteralPath $Root -Force -ErrorAction SilentlyContinue)) {
        $known = $false
        foreach ($pat in $ours) { if ($i.Name -like $pat) { $known = $true; break } }
        if (-not $known) { Write-Host ('Unbekannt im Zielordner: ' + $i.Name); return $true }
    }
    return $false
}

# Datei in den neuen Ordner verschieben. Existiert das Ziel schon (z. B. Log desselben Monats),
# wird der alte Inhalt vorne angefuegt. Danach erbt die Datei die Rechte des neuen Ordners.
function Move-OldFile([string]$Source, [string]$Target) {
    if (Test-Path -LiteralPath $Target) {
        if ($Target -like '*.log') {
            $old = [IO.File]::ReadAllText($Source); $new = [IO.File]::ReadAllText($Target)
            [IO.File]::WriteAllText($Target, $old + $new, (New-Object Text.UTF8Encoding($true)))
            Remove-Item -LiteralPath $Source -Force
        } else {
            Write-Log 'WARN' "Umzug: $(Split-Path $Target -Leaf) gibt es schon im neuen Ordner, alte Datei bleibt liegen."
            return
        }
    } else {
        Move-Item -LiteralPath $Source -Destination $Target
    }
    & icacls.exe $Target /reset | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Log 'WARN' "Umzug: Rechte fuer $(Split-Path $Target -Leaf) nicht zurueckgesetzt (Code $LASTEXITCODE)." }
}

# Umzug der alten Installation (bis V0.9.11). Liefert $false, wenn eine alte Aufgabe gerade laeuft.
function Invoke-Migration {
    $oldTasks = @(Get-ScheduledTask -TaskPath '\' -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like "$OldPrefix*" })
    if ($oldTasks.Count -eq 0 -and -not (Test-Path -LiteralPath $OldRoot)) { return $true }
    Write-Log 'INFO' "Umzug: alte Installation gefunden (Aufgaben: $($oldTasks.Count), alter Ordner vorhanden: $(Test-Path -LiteralPath $OldRoot))"

    $running = @($oldTasks | Where-Object { $_.State -eq 'Running' })
    if ($running.Count -gt 0) {
        Write-Log 'ERROR' ("Umzug abgebrochen: alte Aufgabe laeuft gerade (" + (($running | ForEach-Object { $_.TaskName }) -join ', ') + "). Bitte spaeter erneut installieren.")
        return $false
    }
    if (@($oldTasks | Where-Object { $_.State -eq 'Disabled' }).Count -gt 0) {
        Write-Log 'WARN' 'Umzug: alte Aufgaben waren deaktiviert (Notaus?). Die neuen Aufgaben sind aktiv. Falls noetig: Notaus.bat erneut ausfuehren.'
    }
    foreach ($t in $oldTasks) {
        Unregister-ScheduledTask -TaskPath '\' -TaskName $t.TaskName -Confirm:$false
        Write-Log 'INFO' "Umzug: alte Aufgabe entfernt: $($t.TaskName)"
    }
    $link = Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) $OldLink
    if (Test-Path -LiteralPath $link) { Remove-Item -LiteralPath $link -Force; Write-Log 'INFO' 'Umzug: altes Desktop-Symbol entfernt.' }

    if (-not (Test-Path -LiteralPath $OldRoot)) { return $true }
    $moved = 0
    foreach ($sub in @('Logs', 'State')) {
        $src = Join-Path $OldRoot $sub
        if (-not (Test-Path -LiteralPath $src)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $src -File -Force)) {
            $name = $f.Name
            if ($sub -eq 'Logs') { $name = $name -replace '^WindowsUpdates_', 'PatchPilot_' }
            Move-OldFile $f.FullName (Join-Path (Join-Path $Root $sub) $name)
            $moved++
        }
        if (@(Get-ChildItem -LiteralPath $src -Force).Count -eq 0) { Remove-Item -LiteralPath $src -Force }
    }
    Write-Log 'INFO' "Umzug: $moved Dateien aus Logs und State uebernommen."

    $ownOld = @('Update-*_V*.ps1', 'Uninstall-WindowsUpdates_V*.ps1', 'Install-WindowsUpdates_V*.ps1', 'Notaus_V*.ps1', 'Deinstall.bat', 'Notaus.bat', 'Notaus-Aufheben.bat')
    foreach ($pat in $ownOld) {
        foreach ($f in @(Get-ChildItem -LiteralPath $OldRoot -Filter $pat -File -Force -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $f.FullName -Force }
    }
    $left = @(Get-ChildItem -LiteralPath $OldRoot -Force)
    if ($left.Count -eq 0) {
        Remove-Item -LiteralPath $OldRoot -Force
        Write-Log 'INFO' "Umzug: alter Ordner geloescht: $OldRoot"
    } else {
        Write-Log 'WARN' ("Umzug: im alten Ordner liegen fremde Dateien, Ordner bleibt: " + (($left | ForEach-Object { $_.Name }) -join ', '))
    }
    return $true
}

function Invoke-Main {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'FEHLER: Bitte als Administrator starten.'
        return 1
    }

    # 1. Eingaben pruefen
    $inv = [Globalization.CultureInfo]::InvariantCulture
    try {
        $fr = [datetime]::ParseExact($FridayTime, 'HH:mm', $inv)
        $pr = [datetime]::ParseExact($PreloadTime, 'HH:mm', $inv)
    } catch { Write-Host 'FEHLER: Zeitangaben muessen das Format HH:mm haben.'; return 2 }
    if ($fr.Minute -ne 0) { Write-Host 'FEHLER: -FridayTime muss eine volle Stunde sein (z. B. 06:00).'; return 2 }
    if (-not $SourceDir) { Write-Host 'FEHLER: Das Skript wurde eingefuegt statt als Datei gestartet. Bitte die Datei mit Rechtsklick > "Mit PowerShell ausfuehren" oder per Pfad starten (siehe Anleitung).'; return 2 }
    $missing = @($Payload | Where-Object { -not (Test-Path -LiteralPath (Join-Path $SourceDir $_)) })
    if ($missing.Count) { Write-Host ('FEHLER: Paketdateien fehlen in {0}: {1}' -f $SourceDir, ($missing -join ', ')); return 2 }
    if (Test-ForeignRoot) { Write-Host ('FEHLER: Im Zielordner {0} liegen Dateien, die nicht von Patch Pilot stammen. Nichts installiert.' -f $Root); return 2 }

    # 2. Ordner und Rechte
    foreach ($d in @($Root, $LogDir, (Join-Path $Root 'State'), (Join-Path $Root 'Config'))) { if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }
    Set-Folder-Acl $Root $true
    Set-Folder-Acl (Join-Path $Root 'State') $false
    Set-Folder-Acl (Join-Path $Root 'Config') $false   # Sperrliste und Treiber-Schalter: nur SYSTEM/Administratoren
    Write-Log 'INFO' "Installer $Ver gestartet, Programmordner: $Root"
    Write-Log 'INFO' 'Rechte gesetzt (SYSTEM/Administratoren Vollzugriff, Benutzer lesen/ausfuehren, State nur SYSTEM/Administratoren)'
    if (-not (Invoke-Migration)) { return 3 }

    # 3. Dateien
    foreach ($f in $Payload) {
        if ((Join-Path $SourceDir $f) -ine (Join-Path $Root $f)) { Copy-Item -LiteralPath (Join-Path $SourceDir $f) -Destination (Join-Path $Root $f) -Force }
        Unblock-File -LiteralPath (Join-Path $Root $f) -ErrorAction SilentlyContinue
    }
    foreach ($f in @(Get-ChildItem -LiteralPath $Root -File -Force)) {
        # Eigene Dateien frueherer Versionen (auch alte Namen mit _V-Nummer) und alte Versionsdatei
        $mine = ($f.Name -like 'Update-*.ps1' -or $f.Name -like 'Uninstall-PatchPilot*.ps1' -or $f.Name -like 'Notaus*.ps1' -or $f.Name -like 'Version *')
        if ($f.Name -like 'Install-PatchPilot*.ps1' -and $PSCommandPath -and ($f.FullName -ine $PSCommandPath)) { $mine = $true }
        if ($mine -and ($Payload -notcontains $f.Name)) {
            Remove-Item -LiteralPath $f.FullName -Force
            Write-Log 'INFO' "Veraltete Version entfernt: $($f.Name)"
        }
    }
    Write-Log 'INFO' "Dateien kopiert: $($Payload.Count)"
    # Versionsdatei: leere Datei, deren Name den Stand zeigt
    [IO.File]::WriteAllText((Join-Path $Root "Version $Ver"), '')
    Write-Log 'INFO' "Versionsdatei angelegt: Version $Ver"
    # Pruefung: Alle Module, die Update-Run aufruft, muessen im Programmordner liegen
    $runFile = 'Update-Run.ps1'
    $runText = Get-Content -LiteralPath (Join-Path $Root $runFile) -Raw -Encoding UTF8
    foreach ($m in [regex]::Matches($runText, "'(Update-[A-Za-z]+\.ps1)'")) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $m.Groups[1].Value))) { throw "Modul fehlt im Programmordner: $($m.Groups[1].Value) (von $runFile verlangt)" }
    }
    Write-Log 'INFO' 'Modulpruefung bestanden.'

    # 4. .bat-Dateien
    Write-Bat (Join-Path $Root 'Deinstall.bat') 'Deinstall.bat' 'Uninstall-PatchPilot.ps1'
    Write-Bat (Join-Path $Root 'Notaus.bat') 'Notaus.bat' 'Notaus.ps1'
    Write-Bat (Join-Path $Root 'Notaus-Aufheben.bat') 'Notaus-Aufheben.bat' 'Notaus.ps1' '-Aufheben '
    Write-Bat (Join-Path $Root 'Treiber-Ein.bat') 'Treiber-Ein.bat' 'Update-Option.ps1' '-Action DriversOn '
    Write-Bat (Join-Path $Root 'Treiber-Aus.bat') 'Treiber-Aus.bat' 'Update-Option.ps1' '-Action DriversOff '
    Write-Bat (Join-Path $Root 'Funktionsupdates-Ein.bat') 'Funktionsupdates-Ein.bat' 'Update-Option.ps1' '-Action FeatureOn '
    Write-Bat (Join-Path $Root 'Funktionsupdates-Aus.bat') 'Funktionsupdates-Aus.bat' 'Update-Option.ps1' '-Action FeatureOff '
    Write-Bat (Join-Path $Root 'Direktbezug-Microsoft.bat') 'Direktbezug-Microsoft.bat' 'Update-Option.ps1' '-Action Direct '

    # Sperrliste: nur anlegen, wenn keine da ist (eine vorhandene Liste wird nie ueberschrieben)
    $block = Join-Path $Root 'Config\Sperrliste.txt'
    if (-not (Test-Path -LiteralPath $block)) {
        $tpl = @(
            '# Patch Pilot Sperrliste - gesperrte Updates werden in Windows ausgeblendet und nie installiert.',
            '# Gilt fuer alle Wege (WSUS, Treiber-Zusatz, Direktbezug). Aendern nur als Administrator.',
            '# Eine Zeile pro Eintrag. Erlaubt:',
            '#   KB-Nummer, z. B.  KB5034441',
            '#   Update-ID aus dem Log (steht hinter "ID", vor dem Doppelpunkt), noetig fuer Treiber ohne KB-Nummer',
            '# Zeilen mit # sind Kommentare. Eintrag loeschen = Update wird beim naechsten Lauf wieder eingeblendet.',
            ''
        )
        [IO.File]::WriteAllText($block, (($tpl -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($true)))
        Write-Log 'INFO' 'Sperrliste angelegt (leer): Config\Sperrliste.txt'
    } else { Write-Log 'INFO' 'Sperrliste vorhanden, unveraendert uebernommen.' }
    $drvState = 'an'; if (Test-Path -LiteralPath (Join-Path $Root 'Config\Treiber-Aus')) { $drvState = 'aus' }
    Write-Log 'INFO' "Treiber-Zusatz: $drvState (Einstellung bleibt bei Updates erhalten)"
    $fuState = 'freigegeben'; if (Test-Path -LiteralPath (Join-Path $Root 'Config\Funktionsupdates-Aus')) { $fuState = 'aus' }
    Write-Log 'INFO' "Funktionsupdates: $fuState (Einstellung bleibt bei Updates erhalten)"

    # Hinweis zur Ausfuehrungsrichtlinie
    foreach ($e in @(Get-ExecutionPolicy -List | Where-Object { $_.Scope -in @('MachinePolicy', 'UserPolicy') -and $_.ExecutionPolicy -ne 'Undefined' })) {
        Write-Log 'WARN' ("Gruppenrichtlinie setzt Ausfuehrungsrichtlinie {0} ({1}). Unsignierte Skripte laufen dann nicht." -f $e.ExecutionPolicy, $e.Scope)
    }

    # 5. Aufgaben
    $h = $fr.Hour
    $sys = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $usr = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545' -RunLevel Limited
    $names = @('PatchPilot-Preload', 'PatchPilot-Friday', 'PatchPilot-Boot', 'PatchPilot-Manual', 'PatchPilot-Manual-Shutdown', 'PatchPilot-Fernstart',
               'PatchPilot-User-Ask1', 'PatchPilot-User-Ask2', 'PatchPilot-User-Notice', 'PatchPilot-User-Disconnect',
               'PatchPilot-User-ErrNet', 'PatchPilot-User-ErrFinal', 'PatchPilot-User-ErrPartial', 'PatchPilot-User-ErrManNet', 'PatchPilot-User-ErrManGen', 'PatchPilot-Remind',
               'PatchPilot-User-Running', 'PatchPilot-User-Done', 'PatchPilot-User-Power',
               'PatchPilot-Direct', 'PatchPilot-User-ErrNoOffer', 'PatchPilot-User-Guard', 'PatchPilot-User-Workspace')
    foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -eq '\' -and $_.TaskName -like "$Prefix*" -and $names -notcontains $_.TaskName })) {
        Unregister-ScheduledTask -TaskPath '\' -TaskName $t.TaskName -Confirm:$false
        Write-Log 'INFO' "Veraltete Aufgabe entfernt: $($t.TaskName)"
    }

    $thu = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Thursday -At $pr
    $fri = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Friday -At $fr
    $boot = New-ScheduledTaskTrigger -AtStartup
    $boot.Delay = 'PT1M'
    $logon = New-ScheduledTaskTrigger -AtLogOn
    $logon.Delay = 'PT1M'   # 1 Minute nach der Anmeldung: Anmeldung nicht bremsen, Zeit fuer VPN

    Register-Ctl 'PatchPilot-Preload' 'Update-Run.ps1' "-Mode Preload -FridayHour $h" $sys $thu $false 3
    Register-Ctl 'PatchPilot-Friday' 'Update-Run.ps1' "-Mode Auto -Source Poll -FridayHour $h" $sys $fri $false 3
    Register-Ctl 'PatchPilot-Boot' 'Update-Run.ps1' "-Mode Auto -Source Boot -FridayHour $h" $sys @($boot, $logon) $false 3
    Register-Ctl 'PatchPilot-Remind' 'Update-Run.ps1' "-Mode Auto -Source Remind -FridayHour $h" $sys $null $false 3
    Register-Ctl 'PatchPilot-Manual' 'Update-Run.ps1' "-Mode Manual -FridayHour $h" $sys $null $true 3
    Register-Ctl 'PatchPilot-Manual-Shutdown' 'Update-Run.ps1' "-Mode Manual -ShutdownAfter -FridayHour $h" $sys $null $true 3
    # Start durch die Clientverwaltung ohne Abfrage: nur SYSTEM/Administratoren duerfen starten (nicht durch Benutzer)
    Register-Ctl 'PatchPilot-Fernstart' 'Update-Run.ps1' "-Mode Manual -NoAsk -FridayHour $h" $sys $null $false 3
    # Direktbezug bei Microsoft (Direktbezug-Microsoft.bat): nur SYSTEM/Administratoren
    Register-Ctl 'PatchPilot-Direct' 'Update-Run.ps1' "-Mode Manual -NoAsk -Direct -FridayHour $h" $sys $null $false 3
    Register-Ctl 'PatchPilot-User-Ask1' 'Update-User.ps1' '-Action Ask -Round 1 -TimeoutMinutes 30' $usr $null $false 1
    Register-Ctl 'PatchPilot-User-Ask2' 'Update-User.ps1' '-Action Ask -Round 2 -TimeoutMinutes 60' $usr $null $false 2
    Register-Ctl 'PatchPilot-User-Notice' 'Update-User.ps1' '-Action Notice -NoticeSeconds 30' $usr $null $false 1
    Register-Ctl 'PatchPilot-User-Disconnect' 'Update-User.ps1' '-Action Disconnect' $usr $null $false 1
    Register-Ctl 'PatchPilot-User-Power' 'Update-User.ps1' '-Action Power' $usr $null $false 1
    Register-Ctl 'PatchPilot-User-Guard' 'Update-User.ps1' '-Action Guard -GuardMinutes 250' $usr $null $false 5
    Register-Ctl 'PatchPilot-User-Workspace' 'Update-User.ps1' '-Action Workspace' $usr $null $false 1
    Register-Ctl 'PatchPilot-User-ErrNet' 'Update-Notify.ps1' '-Kind Net -TimeoutMinutes 10' $usr $null $false 1
    Register-Ctl 'PatchPilot-User-ErrFinal' 'Update-Notify.ps1' '-Kind Final -TimeoutMinutes 10' $usr $null $false 1
    Register-Ctl 'PatchPilot-User-ErrNoOffer' 'Update-Notify.ps1' '-Kind NoOffer -TimeoutMinutes 10' $usr $null $false 1
    Register-Ctl 'PatchPilot-User-ErrPartial' 'Update-Notify.ps1' '-Kind Partial -TimeoutMinutes 240' $usr $null $false 5
    Register-Ctl 'PatchPilot-User-ErrManNet' 'Update-Notify.ps1' '-Kind ManualNet -TimeoutMinutes 10' $usr $null $false 1
    Register-Ctl 'PatchPilot-User-ErrManGen' 'Update-Notify.ps1' '-Kind ManualGeneric -TimeoutMinutes 10' $usr $null $false 1
    Register-Ctl 'PatchPilot-User-Running' 'Update-Notify.ps1' '-Kind Running -TimeoutMinutes 10' $usr $null $false 1
    Register-Ctl 'PatchPilot-User-Done' 'Update-Notify.ps1' '-Kind Done -TimeoutMinutes 240' $usr $null $false 5

    # 6. Verknuepfung
    $link = Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'Windows Updates jetzt starten.lnk'
    $sc = (New-Object -ComObject WScript.Shell).CreateShortcut($link)
    $sc.TargetPath = $PsExe
    $sc.Arguments = ('-NoProfile -WindowStyle Minimized -ExecutionPolicy RemoteSigned -File "{0}" -Action Manual' -f (Join-Path $Root 'Update-User.ps1'))
    $sc.WorkingDirectory = $Root
    $sc.Description = "Windows Updates jetzt starten ($Ver)"
    $sc.IconLocation = (Join-Path $env:SystemRoot 'System32\shell32.dll') + ',238'
    $sc.WindowStyle = 7
    $sc.Save()
    Write-Log 'INFO' 'Desktop-Verknuepfung angelegt.'

    Write-Log 'INFO' "Installation abgeschlossen. Donnerstag $PreloadTime Download, Freitag ab $FridayTime Abfrage."
    return 0
}

if (-not $SourceDir -and $PSCommandPath) { $SourceDir = Split-Path -Parent $PSCommandPath }
if (-not $SourceDir -and $MyInvocation.MyCommand.Path) { $SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$code = 3
try { $code = Invoke-Main }
catch { Write-Log 'ERROR' ("Installation fehlgeschlagen: " + $_.Exception.Message + ". Bitte erneut ausfuehren."); $code = 3 }
exit $code
