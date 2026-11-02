#requires -Version 5.1
<#
=====================================================================
Update-Install  (Patch Pilot 0.10.4, installiert nur bereits geladene Updates)
=====================================================================
ZWECK
  Installiert ueber den Windows Update Agent (WUA) alle von WSUS
  freigegebenen Updates, die bereits vollstaendig heruntergeladen sind
  (durch Update-Core). Auch Treiber, Firmware und Funktionsupdates.
  Windows entscheidet selbst ueber Reihenfolge und Neustartbedarf.
  Startet NICHT selbst neu.
  Meldet sich bei Windows Update als 'PatchPilot' (ClientApplicationID), damit
  unsere Installationen im Windows-Updateverlauf erkennbar sind.

ABLAUF
  1. Admin-Pruefung, Schutz gegen Parallelstart (gleicher Mutex wie Update-Core)
  2. WUA frei? (sonst Abbruch mit Exitcode 4)
  3. Lokale Suche aus dem WUA-Zwischenspeicher (Online=false, kein WSUS/VPN)
  4. Jedes Update mit allen Eckdaten ins Log schreiben
  5. Auswahl: alles Geladene. Nicht Geladenes und zurueckgestellte Updates
     (Fehlerregel, siehe unten) werden nicht installiert und geloggt.
  6. Installation nach Microsoft-Muster: normale Updates gemeinsam,
     exklusive Updates (Impact=2) einzeln und nur ohne ausstehenden Neustart.
  7. Ergebnis je Update loggen, Fehlerzaehler fortschreiben
  Sperrliste (Update-Blocklist.ps1): gesperrte Updates werden nie installiert.

FEHLERREGEL (je Update, gezaehlt ueber mehrere Laeufe)
  Fehlversuch = Installation fehlgeschlagen ODER zum Installationszeitpunkt
  nicht geladen. Nach 3 Fehlversuchen wird das Update pro Updatelauf
  (Zyklus) nur noch einmal versucht und das Ergebnis dokumentiert.
  Ein zurueckgestelltes Update haelt den Zyklus nicht offen und loest
  keinen Hinweis aus. Erfolg loescht den Zaehler. Eine neue Revision
  des Updates (von WSUS) beginnt mit einem neuen Zaehler.
  Vorbild: Windows-Regel fuer Firmware-Updates (3 Versuche) und
  Microsoft-Beispiel "Searching, Downloading, and Installing Updates"
  (exklusive Updates einzeln, nur Geladenes installieren).

VORAUSSETZUNGEN
  Windows 11, PowerShell 5.1, Start als Administrator/SYSTEM.
  Updates muessen vorher geladen sein (Update-Core).

SICHERHEIT
  Keine Citrix-Aktion, kein Neustart, keine Aenderung an WSUS/GPO/Registry.
  ACHTUNG: installiert wirklich Updates.

PARAMETER
  -Root      Hauptordner (Standard C:\Fernwartung\PatchPilot)
  -Cycle     Kennung des Updatelaufs (yyyyMMdd des Freitags), von Update-Run
  -MaxTries  Fehlversuche, bevor ein Update nur noch einmal pro Lauf
             versucht wird (Standard 3)
  -SkipFirmware  Firmware-Updates (Treiberklasse Firmware) diesmal nicht
             installieren (Netzteil-Abfrage, Update-Power). Kein Fehlversuch,
             sie werden im naechsten Updatelauf erneut angeboten.

DATEIEN
  <Root>\Logs\PatchPilot_<Jahr-Monat>.log         alles
  <Root>\Logs\PatchPilot_Fehler_<Jahr-Monat>.log  nur Warnungen/Fehler
  <Root>\State\failures.json   Fehlerzaehler je Update (ID, Revision, Titel)

DATENSCHUTZ
  Geloggt werden nur Update-Eckdaten (Titel, KB, Typ, Groesse, ID) und
  Fehlercodes. Keine Benutzer-, Rechner- oder Netzwerkdaten.

EXITCODES
  0  = fertig, kein Neustart noetig (auch: nichts zu installieren)
  10 = fertig, Windows verlangt einen Neustart
  11 = Teilerfolg: Updates offen (fehlgeschlagen/nicht geladen/exklusiv
       wartet) UND Neustart erforderlich
  12 = Teilerfolg: Updates offen, kein Neustart erforderlich
  1  = nicht als Administrator gestartet
  2  = lokale Suche fehlgeschlagen
  3  = Installation nicht moeglich (Install-Aufruf fehlgeschlagen, nichts installiert)
  4  = Windows Update ist gerade belegt
  5  = laeuft bereits (zweite Instanz)
  8  = WSUS nicht aktiv (keine WSUS-Adresse oder UseWUServer ungleich 1):
       nichts installiert (Regel: Patch Pilot installiert nie ohne WSUS-Freigabe)
=====================================================================
#>
[CmdletBinding()]
param(
    [string]$Root = 'C:\Fernwartung\PatchPilot',
    [ValidateRange(0, 99991231)][int]$Cycle = 0,
    [ValidateRange(1, 10)][int]$MaxTries = 3,
    [switch]$SkipFirmware
)

$ErrorActionPreference = 'Stop'
$LogDir   = Join-Path $Root 'Logs'
$Month    = Get-Date -Format 'yyyy-MM'
$LogFile  = Join-Path $LogDir ('PatchPilot_{0}.log' -f $Month)
$ErrFile  = Join-Path $LogDir ('PatchPilot_Fehler_{0}.log' -f $Month)
$FailFile = Join-Path (Join-Path $Root 'State') 'failures.json'
$LogTag = 'Install'

$Hints = @{
    '0x8024200D' = 'Download unvollstaendig oder unbrauchbar, Update muss neu geladen werden (naechster Lauf laedt neu)'
    '0x80240016' = 'Ein anderer Installations- oder Updatevorgang laeuft noch'
    '0x8024001E' = 'Dienst wurde beendet (Neustart oder Dienststopp)'
    '0x80240022' = 'Alle Updates des Aufrufs sind fehlgeschlagen'
    '0x80240020' = 'Installation erfordert eine angemeldete Benutzersitzung'
    '0x80070005' = 'Zugriff verweigert (nicht als Administrator/SYSTEM gestartet?)'
    '0x80070BC2' = 'Neustart erforderlich, bevor die Installation fortgesetzt werden kann'
    '0x80070BC9' = 'Neustart erforderlich, bevor die Installation fortgesetzt werden kann'
}

function Add-LogLine([string]$Path, [string]$Line) {
    # Gemeinsame Datei fuer alle Teile. Schreiben andere gerade, kurz warten und erneut versuchen.
    for ($try = 1; $try -le 10; $try++) {
        try { Add-Content -LiteralPath $Path -Value $Line -Encoding UTF8 -ErrorAction Stop; return } catch { Start-Sleep -Milliseconds (Get-Random -Minimum 50 -Maximum 300) }
    }
}

function Write-Log([string]$Level, [string]$Msg) {
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $LogTag, $Msg
    Add-LogLine $LogFile $line
    if ($Level -eq 'WARN' -or $Level -eq 'ERROR') { Add-LogLine $ErrFile $line }
    Write-Host $line
}

function Get-HrText([int]$Hr) {
    $hex = '0x{0:X8}' -f $Hr
    if ($Hints.ContainsKey($hex)) { return "$hex - $($Hints[$hex])" }
    return $hex
}

# Eindeutiger Schluessel: Update-ID + Revision (neue Revision = neuer Zaehler)
function Get-UpdateKey($U) {
    return ('{0}:{1}' -f $U.Identity.UpdateID, $U.Identity.RevisionNumber)
}

# Alle Eckdaten eines Updates in einer Zeile (fuer die Fehlersuche)
function Get-UpdateInfo($U) {
    $kb = @($U.KBArticleIDs | ForEach-Object { 'KB' + $_ }) -join ','
    if (-not $kb) { $kb = '-' }
    $type = switch ([int]$U.Type) { 1 { 'Software' } 2 { 'Treiber' } default { "Typ $([int]$U.Type)" } }
    $cat = '-'
    try { if ($U.Categories.Count -gt 0) { $cat = $U.Categories.Item(0).Name } } catch { $cat = '?' }
    $mb = '?'
    try { $mb = [math]::Round([double]$U.MaxDownloadSize / 1MB, 1) } catch { $mb = '?' }
    $ib = $U.InstallationBehavior
    if ([int]$U.Type -eq 2) { try { $type = 'Treiber, Klasse ' + [string]$U.DriverClass } catch { $type = 'Treiber' } }
    $excl = 'nein'; if ([int]$ib.Impact -eq 2) { $excl = 'ja' }
    $rb = switch ([int]$ib.RebootBehavior) { 0 { 'nie' } 1 { 'immer' } 2 { 'eventuell' } default { '?' } }
    return ('{0} | {1} | {2} | Kategorie {3} | max. {4} MB | geladen={5} | Eingabe moeglich={6} | exklusiv={7} | Neustart {8} | ID {9}' -f
        $U.Title, $kb, $type, $cat, $mb, $U.IsDownloaded, $ib.CanRequestUserInput, $excl, $rb, (Get-UpdateKey $U))
}

function Get-ResultText([int]$Code) {
    switch ($Code) { 2 { 'ok' } 3 { 'ok mit Fehlern' } 4 { 'fehlgeschlagen' } 5 { 'abgebrochen' } 1 { 'laeuft' } default { 'unbekannt' } }
}

function Test-Firmware($U) {
    if ([int]$U.Type -ne 2) { return $false }
    try { return ([string]$U.DriverClass -eq 'Firmware') } catch { return $false }
}

# ---------------- Fehlerzaehler (State\failures.json) ----------------
function Read-Failures {
    $map = @{}
    if (-not (Test-Path -LiteralPath $FailFile)) { return $map }
    try {
        $list = @(Get-Content -LiteralPath $FailFile -Raw -Encoding UTF8 | ConvertFrom-Json)
        foreach ($e in $list) {
            if ($e -and $e.Key) { $map[[string]$e.Key] = [pscustomobject]@{ Key = [string]$e.Key; Title = [string]$e.Title; Fails = [int]$e.Fails; LastCycle = [int]$e.LastCycle } }
        }
    } catch {
        Write-Log 'WARN' 'Fehlerzaehler-Datei unlesbar, wird als .bad beiseite gelegt und neu begonnen.'
        try { Move-Item -LiteralPath $FailFile -Destination ($FailFile + '.bad') -Force } catch { Write-Log 'WARN' 'Fehlerzaehler-Datei konnte nicht umbenannt werden.' }
        $map = @{}
    }
    return $map
}

function Save-Failures($Map) {
    $dir = Split-Path -Parent $FailFile
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $tmp = $FailFile + '.tmp'
    $json = ConvertTo-Json -InputObject @($Map.Values | Sort-Object Key) -Depth 3
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $FailFile) { [IO.File]::Replace($tmp, $FailFile, [NullString]::Value) }
    else { [IO.File]::Move($tmp, $FailFile) }
}

# Zaehlt einen Fehlversuch. Liefert $true, wenn das Update damit zurueckgestellt ist (Zyklus bleibt nicht offen).
function Add-Failure($Map, $U, [string]$Why) {
    $key = Get-UpdateKey $U
    $rec = $Map[$key]
    if (-not $rec) { $rec = [pscustomobject]@{ Key = $key; Title = [string]$U.Title; Fails = 0; LastCycle = 0 }; $Map[$key] = $rec }
    $rec.Fails = $rec.Fails + 1
    $rec.LastCycle = $script:CycleId
    if ($rec.Fails -ge $MaxTries) {
        Write-Log 'ERROR' ("Fehlversuch {0} ({1}): {2}. Zurueckgestellt, naechster Versuch im naechsten Updatelauf." -f $rec.Fails, $Why, $U.Title)
        return $true
    }
    Write-Log 'ERROR' ("Fehlversuch {0} von {1} ({2}): {3}. Wird erneut versucht." -f $rec.Fails, $MaxTries, $Why, $U.Title)
    return $false
}

# Installiert eine Sammlung, wertet jedes Update aus. Liefert $null, wenn der Aufruf selbst scheitert.
function Invoke-InstallBatch($Session, $Coll, $Map, [string]$Label) {
    $inst = $Session.CreateUpdateInstaller()
    $inst.Updates = $Coll
    $inst.AllowSourcePrompts = $false
    $inst.IsForced = $false
    Write-Log 'INFO' ("Phase Installation ({0}): Aktion Install() mit {1} Updates" -f $Label, $Coll.Count)
    try {
        $res = $inst.Install()
    } catch {
        Write-Log 'ERROR' ("Install-Aufruf fehlgeschlagen ({0}): {1}" -f $Label, (Get-HrText $_.Exception.HResult))
        return $null
    }
    $out = [pscustomobject]@{ Ok = 0; Open = 0; Reboot = [bool]$res.RebootRequired }
    for ($i = 0; $i -lt $Coll.Count; $i++) {
        $u = $Coll.Item($i)
        $ur = $res.GetUpdateResult($i)
        if ([int]$ur.ResultCode -eq 2) {
            $out.Ok++
            Write-Log 'INFO' ("Installiert: {0} (Neustart noetig: {1})" -f $u.Title, [bool]$ur.RebootRequired)
            $key = Get-UpdateKey $u
            if ($Map.ContainsKey($key)) { $Map.Remove($key) }
        } else {
            $why = '{0} (ResultCode {1}), {2}' -f (Get-ResultText ([int]$ur.ResultCode)), $ur.ResultCode, (Get-HrText $ur.HResult)
            if (-not (Add-Failure $Map $u $why)) { $out.Open++ }
        }
    }
    Write-Log 'INFO' ("Ergebnis ({0}): {1} (ResultCode {2}), {3}, erfolgreich: {4} von {5}, Neustart erforderlich: {6}" -f $Label, (Get-ResultText ([int]$res.ResultCode)), $res.ResultCode, (Get-HrText $res.HResult), $out.Ok, $Coll.Count, $out.Reboot)
    return $out
}

function Test-RebootPending {
    try { return [bool](New-Object -ComObject Microsoft.Update.SystemInfo).RebootRequired } catch { return $false }
}

function Invoke-Main {
    # Phase 1: Admin-Pruefung
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'FEHLER: Bitte als Administrator starten.'
        return 1
    }
    if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    $script:CycleId = $Cycle
    if ($script:CycleId -eq 0) { $script:CycleId = [int](Get-Date -Format 'yyyyMMdd') }
    Write-Log 'INFO' "Update-Install gestartet (Patch Pilot 0.10.4, Updatelauf $($script:CycleId))"

    # WSUS laut Registry aktiv? Sonst nichts installieren (lokale Liste koennte von Microsoft statt WSUS stammen)
    $wu = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue
    $au = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -ErrorAction SilentlyContinue
    if (-not ($wu -and $wu.WUServer -and $au -and $au.UseWUServer -eq 1)) {
        Write-Log 'ERROR' 'WSUS nicht aktiv (keine WSUS-Adresse oder UseWUServer ungleich 1). Nichts installiert: Patch Pilot installiert nie ohne WSUS-Freigabe.'
        return 8
    }

    $rebootBefore = Test-RebootPending
    Write-Log 'INFO' "Neustart vor Start ausstehend (Windows-Status): $rebootBefore"

    # Phase 2: WUA frei?
    $session = New-Object -ComObject Microsoft.Update.Session
    $session.ClientApplicationID = 'PatchPilot'   # Kennung im Windows-Updateverlauf (wie im Microsoft-Beispiel)
    if ($session.CreateUpdateInstaller().IsBusy) {
        Write-Log 'ERROR' 'Windows Update ist belegt. Naechster Schritt: spaeterer Lauf'
        return 4
    }

    # Phase 3: Lokale Suche (kein Netzwerk)
    try {
        $searcher = $session.CreateUpdateSearcher()
        $searcher.ServerSelection = 0
        $searcher.Online = $false
        Write-Log 'INFO' 'Phase Suche: lokal (Online=false)'
        $found = $searcher.Search('IsInstalled=0 and IsHidden=0')
    } catch {
        Write-Log 'ERROR' ("Lokale Suche fehlgeschlagen: {0}. Naechster Schritt: Update-Core ausfuehren" -f (Get-HrText $_.Exception.HResult))
        return 2
    }
    Write-Log 'INFO' "Gefunden: $($found.Updates.Count)"
    # Sperrliste: gesperrte Updates ausblenden und nicht installieren (z. B. nach dem Download gesperrt)
    $blocked = Set-BlockedHidden $found.Updates
    Add-FeatureSkips $found.Updates $blocked

    # Phase 4+5: Eckdaten loggen und auswaehlen
    $map = Read-Failures
    $normal = New-Object -ComObject Microsoft.Update.UpdateColl
    $exclusive = New-Object System.Collections.ArrayList
    $open = 0; $deferred = 0; $fwSkipped = 0
    foreach ($u in $found.Updates) {
        if ($blocked.ContainsKey(([string]$u.Identity.UpdateID).ToLowerInvariant())) { continue }
        Write-Log 'INFO' ('Update: ' + (Get-UpdateInfo $u))
        if ($SkipFirmware -and (Test-Firmware $u)) {
            Write-Log 'WARN' ("Firmware diesmal nicht installiert (Netzteil-Abfrage), kein Fehlversuch, naechster Updatelauf: {0}" -f $u.Title)
            $fwSkipped++
            continue
        }
        $rec = $map[(Get-UpdateKey $u)]
        if ($rec -and $rec.Fails -ge $MaxTries -and $rec.LastCycle -eq $script:CycleId) {
            Write-Log 'WARN' ("Zurueckgestellt bis zum naechsten Updatelauf ({0} Fehlversuche): {1}" -f $rec.Fails, $u.Title)
            $deferred++
            continue
        }
        if (-not $u.IsDownloaded) {
            if (-not (Add-Failure $map $u 'nicht geladen, wird beim naechsten Download nachgeladen')) { $open++ }
            continue
        }
        if (-not $u.EulaAccepted) { $u.AcceptEula() }
        if ([int]$u.InstallationBehavior.Impact -eq 2) { [void]$exclusive.Add($u) } else { [void]$normal.Add($u) }
    }
    Write-Log 'INFO' ("Auswahl: normal {0}, exklusiv {1}, offen (nicht geladen) {2}, zurueckgestellt {3}, Firmware ausgelassen {4}" -f $normal.Count, $exclusive.Count, $open, $deferred, $fwSkipped)

    # Phase 6: Installation (Microsoft-Muster: normale gemeinsam, exklusive einzeln)
    $ok = 0; $reboot = $rebootBefore; $callFailed = $false
    if ($normal.Count -gt 0) {
        $r = Invoke-InstallBatch $session $normal $map 'normal'
        if ($null -eq $r) { $callFailed = $true; $open += $normal.Count }
        else { $ok += $r.Ok; $open += $r.Open; if ($r.Reboot) { $reboot = $true } }
    }
    foreach ($u in $exclusive) {
        if ($reboot -or (Test-RebootPending)) {
            # Microsoft-Beispiel: exklusives Update spaeter installieren (hier: nach dem Neustart, naechster Lauf)
            Write-Log 'WARN' ("Exklusives Update wartet auf den Neustart (kein Fehlversuch): {0}" -f $u.Title)
            $reboot = $true; $open++
            continue
        }
        $one = New-Object -ComObject Microsoft.Update.UpdateColl
        [void]$one.Add($u)
        $r = Invoke-InstallBatch $session $one $map 'exklusiv'
        if ($null -eq $r) { $callFailed = $true; $open++ }
        else { $ok += $r.Ok; $open += $r.Open; if ($r.Reboot) { $reboot = $true } }
    }

    try { Save-Failures $map } catch { Write-Log 'ERROR' ("Fehlerzaehler nicht speicherbar: " + $_.Exception.Message) }
    if (-not $reboot) { $reboot = Test-RebootPending }
    Write-Log 'INFO' "Gesamt: installiert $ok, offen $open, zurueckgestellt $deferred, Neustart erforderlich: $reboot"

    # Phase 7: Exitcode
    if ($callFailed -and $ok -eq 0) {
        Write-Log 'ERROR' 'Installation nicht moeglich. Naechster Schritt: spaeterer Lauf.'
        return 3
    }
    if ($open -gt 0) {
        if ($reboot) { Write-Log 'WARN' 'Teilerfolg, Updates offen, Neustart erforderlich.'; return 11 }
        Write-Log 'WARN' 'Teilerfolg, Updates offen.'
        return 12
    }
    if ($reboot) { Write-Log 'INFO' 'Fertig, Neustart erforderlich. Dieses Modul startet nicht neu.'; return 10 }
    Write-Log 'INFO' 'Fertig, kein Neustart noetig.'
    return 0
}

# Sperrliste (gemeinsame Funktionen)
try { . (Join-Path $PSScriptRoot 'Update-Blocklist.ps1') }
catch { Write-Host ('Sperrliste nicht ladbar: ' + $_.Exception.Message); exit 3 }

# Schutz gegen Parallelstart (gleicher Mutex wie Update-Core)
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
