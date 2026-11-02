#requires -Version 5.1
<#
=====================================================================
Update-Microsoft  (Patch Pilot 0.10.4, Updates direkt von Windows Update)
=====================================================================
ZWECK
  Sucht, laedt und installiert Updates direkt bei Microsoft (Windows Update),
  ohne WSUS. Zwei Umfaenge (-Scope):
    Drivers  Weg 1 "Treiber-Zusatz": nur Treiber und Firmware, die Windows
             als wichtig einstuft. Laeuft zusaetzlich zu den WSUS-Updates
             (ein- und ausschaltbar mit Treiber-Ein.bat / Treiber-Aus.bat).
    All      Weg 2 "Direktbezug": alle wichtigen Updates (wie der Windows-
             Knopf "Online nach Updates von Microsoft Update suchen"),
             nach 45 Tagen ohne WSUS oder per Direktbezug-Microsoft.bat.
  Zwei Schritte (-Action): Download (vor dem Citrix-Hinweis) und Install
  (nach der Citrix-Trennung, zusammen mit den WSUS-Updates).

VORBILD
  Microsoft-Dokumentation IUpdateSearcher::Search (Suchkriterien) und
  PSWindowsUpdate (Get-WindowsUpdate -WindowsUpdate -UpdateType Driver,
  -NotTitle): gleiche Windows-Update-Schnittstelle wie Update-Core.
  Quelle: ServerSelection 2 = Windows Update (immer vorhanden, ohne Office).
  Suchkriterien:
    Drivers  IsInstalled=0 and IsHidden=0 and Type='Driver' and BrowseOnly=0
    All      IsInstalled=0 and IsHidden=0 and BrowseOnly=0
  Type='Driver' schliesst alle Software-Updates aus. BrowseOnly=0 schliesst
  optionale Updates aus (dazu gehoeren die monatlichen Vorschau-Updates und
  optionale Treiber). Zusaetzlich: Titel mit "Preview" oder "Vorschau" werden
  nie genommen (wie PSWindowsUpdate -NotTitle). Sperrliste: Update-Blocklist.

FIRMWARE
  Nur mit Netzteil oder ab 50 % Akku (Regel wie Update-Power), sonst
  naechster Updatelauf. -SkipFirmware (Netzteil-Abfrage "Spaeter") laesst
  Firmware immer aus. Kein Fehlversuch.

FEHLERREGEL (wie Update-Install, eigener Zaehler State\failures_microsoft.json)
  Nach 3 Fehlversuchen nur noch einmal pro Updatelauf versuchen, nie aufgeben.
  Treiber-Zusatz (ab 0.10.1): ein Treiber mit 3 Fehlversuchen zaehlt im
  Download-Schritt nicht mehr als "bereit" und loest allein keinen
  Installationslauf aus; er wird nur noch zusammen mit WSUS-Updates versucht.

VORAUSSETZUNGEN
  Windows 11, PowerShell 5.1, Start als Administrator/SYSTEM, Internet.
  Nicht moeglich, wenn eine Gruppenrichtlinie den Zugriff auf Windows Update
  sperrt (DoNotConnectToWindowsUpdateInternetLocations oder
  DisableWindowsUpdateAccess): dann Exitcode 9, nichts getan.

SICHERHEIT
  Keine Citrix-Aktion, kein Neustart, keine Aenderung an WSUS/GPO.
  Download: nur Laden. Install: installiert wirklich Updates.

PARAMETER
  -Scope         Drivers | All
  -Action        Download | Install
  -Root          Hauptordner (Standard C:\Fernwartung\PatchPilot)
  -Cycle         Kennung des Updatelaufs (von Update-Run)
  -MaxTries      Fehlversuche bis zum Zurueckstellen (Standard 3)
  -SkipFirmware  Firmware diesmal auslassen
  -SearchTimeoutSeconds  Hoechstdauer der Suche (Standard 600)

DATENSCHUTZ
  Geloggt werden nur Update-Eckdaten und Fehlercodes.

EXITCODES
  Download: 0 = alles geladen, 6 = nichts gefunden, 3 = nichts geladen,
            4 = teilweise geladen, 7 = nur zurueckgestellte Treiber (ab 0.10.1)
  Install:  0 = fertig (auch: nichts zu installieren), 10 = fertig, Neustart
            noetig, 11 = Teilerfolg + Neustart, 12 = Teilerfolg,
            3 = Installation nicht moeglich, 4 = Windows Update belegt
  Beide:    1 = nicht als Administrator, 2 = Suche fehlgeschlagen (Internet),
            5 = laeuft bereits, 9 = Windows Update per Richtlinie gesperrt
=====================================================================
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Drivers','All')][string]$Scope,
    [Parameter(Mandatory)][ValidateSet('Download','Install')][string]$Action,
    [string]$Root = 'C:\Fernwartung\PatchPilot',
    [int]$Cycle = 0,
    [ValidateRange(1, 10)][int]$MaxTries = 3,
    [switch]$SkipFirmware,
    [ValidateRange(60, 3600)][int]$SearchTimeoutSeconds = 600,
    [ValidateRange(1, 5)][int]$MaxAttempts = 2
)

$ErrorActionPreference = 'Stop'
$LogDir   = Join-Path $Root 'Logs'
$Month    = Get-Date -Format 'yyyy-MM'
$LogFile  = Join-Path $LogDir ('PatchPilot_{0}.log' -f $Month)
$ErrFile  = Join-Path $LogDir ('PatchPilot_Fehler_{0}.log' -f $Month)
$FailFile = Join-Path $Root 'State\failures_microsoft.json'
$LogTag   = 'Microsoft'
if ($Scope -eq 'Drivers') { $LogTag = 'Treiber' }
$MinPercent = 50
$Label = 'Direktbezug (alle wichtigen Updates)'
if ($Scope -eq 'Drivers') { $Label = 'Treiber-Zusatz (wichtige Treiber/Firmware)' }
$Criteria = 'IsInstalled=0 and IsHidden=0 and BrowseOnly=0'
if ($Scope -eq 'Drivers') { $Criteria = "IsInstalled=0 and IsHidden=0 and Type='Driver' and BrowseOnly=0" }
$script:CycleId = 0

$Hints = @{
    '0x8024402C' = 'Servername nicht aufloesbar (Internet pruefen)'
    '0x80072EE7' = 'Servername nicht aufloesbar (Internet pruefen)'
    '0x80072EFD' = 'Verbindung nicht moeglich (Internet pruefen)'
    '0x80072EE2' = 'Zeitueberschreitung bei der Verbindung (Internet pruefen)'
    '0x8024200D' = 'Download unvollstaendig, wird neu geladen'
    '0x8024001E' = 'Dienst wurde beendet (Neustart oder Dienststopp)'
    '0x80240016' = 'Ein anderer Installations- oder Updatevorgang laeuft noch'
    '0x8024002E' = 'Zugriff auf Windows Update per Richtlinie gesperrt'
}

function Add-LogLine([string]$Path, [string]$Line) {
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

function Get-ResultText([int]$Code) {
    switch ($Code) { 2 { 'ok' } 3 { 'ok mit Fehlern' } 4 { 'fehlgeschlagen' } 5 { 'abgebrochen' } 1 { 'laeuft' } default { 'unbekannt' } }
}

function Get-UpdateKey($U) { return ('{0}:{1}' -f $U.Identity.UpdateID, $U.Identity.RevisionNumber) }

function Get-UpdateInfo($U) {
    $kb = @($U.KBArticleIDs | ForEach-Object { 'KB' + $_ }) -join ','
    if (-not $kb) { $kb = '-' }
    $type = 'Software'
    if ([int]$U.Type -eq 2) { try { $type = 'Treiber, Klasse ' + [string]$U.DriverClass } catch { $type = 'Treiber' } }
    $mb = '?'
    try { $mb = [math]::Round([double]$U.MaxDownloadSize / 1MB, 1) } catch { $mb = '?' }
    return ('{0} | {1} | {2} | max. {3} MB | geladen={4} | Quelle Windows Update | ID {5}' -f $U.Title, $kb, $type, $mb, $U.IsDownloaded, (Get-UpdateKey $U))
}

function Test-Firmware($U) {
    if ([int]$U.Type -ne 2) { return $false }
    try { return ([string]$U.DriverClass -eq 'Firmware') } catch { return $false }
}

# Sperrt eine Gruppenrichtlinie den Zugriff auf Windows Update? (dann geht dieser Weg nicht)
function Test-WuBlockedByPolicy {
    $wu = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue
    if ($wu -and $wu.DoNotConnectToWindowsUpdateInternetLocations -eq 1) { return 'DoNotConnectToWindowsUpdateInternetLocations = 1' }
    if ($wu -and $wu.DisableWindowsUpdateAccess -eq 1) { return 'DisableWindowsUpdateAccess = 1' }
    return ''
}

# Stromstatus laut Windows (wie Update-Power)
function Test-FirmwareAllowedByPower {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $ps = [System.Windows.Forms.SystemInformation]::PowerStatus
        $noBattery = (($ps.BatteryChargeStatus -band [System.Windows.Forms.BatteryChargeStatus]::NoSystemBattery) -ne 0)
        if ($noBattery -or [string]$ps.PowerLineStatus -eq 'Online') { return $true }
        $percent = [int][math]::Round($ps.BatteryLifePercent * 100)
        Write-Log 'INFO' "Strom: Akkubetrieb, Akku $percent %"
        return ($percent -ge $MinPercent)
    } catch {
        # Wie Update-Power: Pruefung nicht moeglich -> normal weiter (Windows/Firmware pruefen selbst)
        Write-Log 'WARN' ('Stromstatus nicht lesbar: ' + $_.Exception.GetType().Name + '. Firmware wird normal behandelt.')
        return $true
    }
}

# ---------------- Fehlerzaehler (wie Update-Install) ----------------
function Read-Failures {
    $map = @{}
    if (-not (Test-Path -LiteralPath $FailFile)) { return $map }
    try {
        foreach ($e in @(Get-Content -LiteralPath $FailFile -Raw -Encoding UTF8 | ConvertFrom-Json)) {
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
    [IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject @($Map.Values | Sort-Object Key) -Depth 3), (New-Object Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $FailFile) { [IO.File]::Replace($tmp, $FailFile, [NullString]::Value) }
    else { [IO.File]::Move($tmp, $FailFile) }
}

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

# ---------------- Suche ----------------
function Invoke-Search($Session, [bool]$Online) {
    $searcher = $Session.CreateUpdateSearcher()
    $searcher.ServerSelection = 2      # 2 = Windows Update (direkt bei Microsoft, ohne WSUS)
    $searcher.Online = $Online
    $where = 'online'; if (-not $Online) { $where = 'lokal' }
    Write-Log 'INFO' ("Phase Suche ($where, Windows Update): $Criteria")
    if (-not $Online) { return $searcher.Search($Criteria) }
    $job = $null
    try { $job = $searcher.BeginSearch($Criteria, $null, $null) } catch { $job = $null }
    if (-not $job) { return $searcher.Search($Criteria) }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while (-not $job.IsCompleted -and $sw.Elapsed.TotalSeconds -lt $SearchTimeoutSeconds) { Start-Sleep -Seconds 2 }
    if (-not $job.IsCompleted) {
        try { $job.RequestAbort() } catch { Write-Log 'WARN' 'Suche liess sich nicht abbrechen.' }
        throw [TimeoutException]::new("Suche nach $SearchTimeoutSeconds s abgebrochen")
    }
    return $searcher.EndSearch($job)
}

# Filter: Vorschau nie, Sperrliste (in Windows ausblenden), bei Treibern nur Typ Treiber.
function Select-Wanted($Updates) {
    $blocked = Set-BlockedHidden $Updates
    Add-FeatureSkips $Updates $blocked
    $keep = New-Object System.Collections.ArrayList
    foreach ($u in $Updates) {
        $id = ([string]$u.Identity.UpdateID).ToLowerInvariant()
        if ($blocked.ContainsKey($id)) { continue }
        if ([string]$u.Title -match '(?i)preview|vorschau') { Write-Log 'INFO' ('Vorschau, nicht genommen: ' + $u.Title); continue }
        if ($Scope -eq 'Drivers' -and [int]$u.Type -ne 2) { Write-Log 'WARN' ('Kein Treiber, nicht genommen: ' + $u.Title); continue }
        [void]$keep.Add($u)
    }
    return , $keep
}

# ---------------- Download ----------------
function Invoke-Download($Session) {
    try { $found = Invoke-Search $Session $true }
    catch {
        Write-Log 'ERROR' ("Suche bei Windows Update fehlgeschlagen: {0}. Naechster Schritt: spaeterer Lauf" -f (Get-HrText $_.Exception.HResult))
        return 2
    }
    Restore-UnblockedUpdates $Session 2 $true
    $list = Select-Wanted $found.Updates
    $deferredDrv = 0
    if ($Scope -eq 'Drivers') {
        # Treiber, die schon $MaxTries-mal nicht installiert werden konnten, zaehlen nicht als "bereit":
        # sie loesen allein keinen Installationslauf (Citrix-Trennung) mehr aus. Mitinstalliert werden sie
        # weiterhin, wenn der WSUS ohnehin Updates bringt (Install-Schritt, nie aufgeben).
        $map = Read-Failures
        $keep = New-Object System.Collections.ArrayList
        foreach ($u in $list) {
            $rec = $map[(Get-UpdateKey $u)]
            if ($rec -and $rec.Fails -ge $MaxTries) {
                Write-Log 'WARN' ("Treiber nach {0} Fehlversuchen nur noch zusammen mit WSUS-Updates: {1}" -f $rec.Fails, $u.Title)
                $deferredDrv++; continue
            }
            [void]$keep.Add($u)
        }
        $list = $keep
    }
    Write-Log 'INFO' ("Gefunden: {0}, davon genommen: {1}" -f $found.Updates.Count, $list.Count)
    if ($list.Count -eq 0 -and $deferredDrv -gt 0) { Write-Log 'INFO' 'Nur zurueckgestellte Treiber vorhanden: kein eigener Installationslauf.'; return 7 }
    if ($list.Count -eq 0) { Write-Log 'INFO' 'Nichts zu laden.'; return 6 }

    $need = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($u in $list) {
        Write-Log 'INFO' ('Update: ' + (Get-UpdateInfo $u))
        if (-not $u.EulaAccepted) { $u.AcceptEula() }
        if (-not $u.IsDownloaded) { [void]$need.Add($u) }
    }
    $attempt = 0
    while ($need.Count -gt 0 -and $attempt -lt $MaxAttempts) {
        $attempt++
        Write-Log 'INFO' "Phase Download: Versuch $attempt von $MaxAttempts, Updates: $($need.Count)"
        try {
            $dl = $Session.CreateUpdateDownloader()
            $dl.Updates = $need
            $res = $dl.Download()
            Write-Log 'INFO' ("Download-Ergebnis: {0}, {1}" -f (Get-ResultText ([int]$res.ResultCode)), (Get-HrText $res.HResult))
        } catch {
            Write-Log 'WARN' ("Download-Aufruf fehlgeschlagen: {0}" -f (Get-HrText $_.Exception.HResult))
        }
        $still = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($u in $need) { if (-not $u.IsDownloaded) { [void]$still.Add($u) } }
        $need = $still
        if ($need.Count -gt 0 -and $attempt -lt $MaxAttempts) { Start-Sleep -Seconds 30 }
    }
    if ($need.Count -eq 0) { Write-Log 'INFO' "Alle $($list.Count) Updates geladen."; return 0 }
    foreach ($u in $need) { Write-Log 'WARN' ('Nicht geladen: ' + $u.Title) }
    if ($need.Count -lt $list.Count) { Write-Log 'WARN' "Teilweise geladen: $($list.Count - $need.Count) von $($list.Count)."; return 4 }
    Write-Log 'ERROR' 'Nichts geladen. Naechster Schritt: spaeterer Lauf'
    return 3
}

# ---------------- Installation ----------------
function Invoke-InstallBatch($Session, $Coll, $Map, [string]$What) {
    $inst = $Session.CreateUpdateInstaller()
    $inst.Updates = $Coll
    $inst.AllowSourcePrompts = $false
    $inst.IsForced = $false
    Write-Log 'INFO' ("Phase Installation ({0}): {1} Updates" -f $What, $Coll.Count)
    try { $res = $inst.Install() }
    catch {
        Write-Log 'ERROR' ("Install-Aufruf fehlgeschlagen ({0}): {1}" -f $What, (Get-HrText $_.Exception.HResult))
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
    return $out
}

function Test-RebootPending {
    try { return [bool](New-Object -ComObject Microsoft.Update.SystemInfo).RebootRequired } catch { return $false }
}

function Invoke-Install($Session) {
    if ($Session.CreateUpdateInstaller().IsBusy) { Write-Log 'ERROR' 'Windows Update ist belegt. Naechster Schritt: spaeterer Lauf'; return 4 }
    $rebootBefore = Test-RebootPending
    # Zuerst lokal (ohne Netzwerk, wie Update-Install). Findet die lokale Suche nichts oder geht sie nicht,
    # einmal online suchen (die Suche bei Windows Update kennt die geladenen Updates sicher).
    $found = $null
    try { $found = Invoke-Search $Session $false } catch { Write-Log 'INFO' ("Lokale Suche nicht moeglich ({0}), suche online." -f (Get-HrText $_.Exception.HResult)) }
    if ($null -eq $found -or $found.Updates.Count -eq 0) {
        try { $found = Invoke-Search $Session $true }
        catch {
            Write-Log 'ERROR' ("Suche bei Windows Update fehlgeschlagen: {0}. Naechster Schritt: spaeterer Lauf" -f (Get-HrText $_.Exception.HResult))
            return 2
        }
    }
    $list = Select-Wanted $found.Updates
    $fwOk = $true
    if ($SkipFirmware) { $fwOk = $false; Write-Log 'INFO' 'Firmware diesmal ausgelassen (Netzteil-Abfrage).' }
    elseif (@($list | Where-Object { Test-Firmware $_ }).Count -gt 0) { $fwOk = Test-FirmwareAllowedByPower }

    $map = Read-Failures
    $normal = New-Object -ComObject Microsoft.Update.UpdateColl
    $exclusive = New-Object System.Collections.ArrayList
    $open = 0; $deferred = 0; $fwSkipped = 0; $notLoaded = 0
    foreach ($u in $list) {
        Write-Log 'INFO' ('Update: ' + (Get-UpdateInfo $u))
        if ((Test-Firmware $u) -and -not $fwOk) {
            Write-Log 'WARN' ("Firmware diesmal nicht installiert (Netzteil/Akku unter $MinPercent %), kein Fehlversuch, naechster Updatelauf: {0}" -f $u.Title)
            $fwSkipped++; continue
        }
        $rec = $map[(Get-UpdateKey $u)]
        if ($rec -and $rec.Fails -ge $MaxTries -and $rec.LastCycle -eq $script:CycleId) {
            Write-Log 'WARN' ("Zurueckgestellt bis zum naechsten Updatelauf ({0} Fehlversuche): {1}" -f $rec.Fails, $u.Title)
            $deferred++; continue
        }
        if (-not $u.IsDownloaded) {
            # Nicht geladen ist hier kein Fehlversuch: es wird beim naechsten Download-Schritt geladen.
            Write-Log 'INFO' ('Noch nicht geladen, naechster Lauf: ' + $u.Title)
            $notLoaded++; continue
        }
        if (-not $u.EulaAccepted) { $u.AcceptEula() }
        if ([int]$u.InstallationBehavior.Impact -eq 2) { [void]$exclusive.Add($u) } else { [void]$normal.Add($u) }
    }
    Write-Log 'INFO' ("Auswahl: normal {0}, exklusiv {1}, nicht geladen {2}, zurueckgestellt {3}, Firmware ausgelassen {4}" -f $normal.Count, $exclusive.Count, $notLoaded, $deferred, $fwSkipped)
    if ($normal.Count -eq 0 -and $exclusive.Count -eq 0) {
        Write-Log 'INFO' 'Nichts zu installieren.'
        if ($rebootBefore) { return 10 }
        return 0
    }

    $ok = 0; $reboot = $rebootBefore; $callFailed = $false
    if ($normal.Count -gt 0) {
        $r = Invoke-InstallBatch $Session $normal $map 'normal'
        if ($null -eq $r) { $callFailed = $true; $open += $normal.Count }
        else { $ok += $r.Ok; $open += $r.Open; if ($r.Reboot) { $reboot = $true } }
    }
    foreach ($u in $exclusive) {
        if ($reboot -or (Test-RebootPending)) {
            Write-Log 'WARN' ("Exklusives Update wartet auf den Neustart (kein Fehlversuch): {0}" -f $u.Title)
            $reboot = $true; $open++; continue
        }
        $one = New-Object -ComObject Microsoft.Update.UpdateColl
        [void]$one.Add($u)
        $r = Invoke-InstallBatch $Session $one $map 'exklusiv'
        if ($null -eq $r) { $callFailed = $true; $open++ }
        else { $ok += $r.Ok; $open += $r.Open; if ($r.Reboot) { $reboot = $true } }
    }
    try { Save-Failures $map } catch { Write-Log 'ERROR' ("Fehlerzaehler nicht speicherbar: " + $_.Exception.Message) }
    if (-not $reboot) { $reboot = Test-RebootPending }
    Write-Log 'INFO' "Gesamt: installiert $ok, offen $open, zurueckgestellt $deferred, Neustart erforderlich: $reboot"
    if ($callFailed -and $ok -eq 0) { Write-Log 'ERROR' 'Installation nicht moeglich. Naechster Schritt: spaeterer Lauf.'; return 3 }
    if ($open -gt 0) { if ($reboot) { return 11 }; return 12 }
    if ($reboot) { return 10 }
    return 0
}

function Invoke-Main {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'FEHLER: Bitte als Administrator starten.'
        return 1
    }
    if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    $script:CycleId = $Cycle
    if ($script:CycleId -eq 0) { $script:CycleId = [int](Get-Date -Format 'yyyyMMdd') }
    Write-Log 'INFO' "Update-Microsoft gestartet (Patch Pilot 0.10.4, $Label, Schritt $Action)"

    $why = Test-WuBlockedByPolicy
    if ($why) {
        Write-Log 'ERROR' "Windows Update per Gruppenrichtlinie gesperrt ($why). Dieser Weg ist auf diesem PC nicht moeglich, nichts getan."
        return 9
    }
    if ($Scope -eq 'Drivers') {
        $wu = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue
        if ($wu -and $wu.ExcludeWUDriversInQualityUpdate -eq 1) { Write-Log 'WARN' 'Richtlinie "Keine Treiber in Windows-Qualitaetsupdates" ist gesetzt: Windows Update bietet evtl. keine Treiber an.' }
    }

    $session = New-Object -ComObject Microsoft.Update.Session
    $session.ClientApplicationID = 'PatchPilot'
    if ($Action -eq 'Download') { return (Invoke-Download $session) }
    return (Invoke-Install $session)
}

# Sperrliste (gemeinsame Funktionen)
try { . (Join-Path $PSScriptRoot 'Update-Blocklist.ps1') }
catch { Write-Host ('Sperrliste nicht ladbar: ' + $_.Exception.Message); exit 3 }

# Schutz gegen Parallelstart (gleicher Mutex wie Update-Core und Update-Install)
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Global\PatchPilot_UpdateCore', [ref]$created)
if (-not $created) {
    Write-Host 'Ein anderes Update-Modul laeuft bereits. Abbruch.'
    exit 5
}
$code = 3
try { $code = [int](@(Invoke-Main)[-1]) }
catch {
    Write-Host ("Unerwarteter Fehler: " + $_.Exception.Message)
    try { Write-Log 'ERROR' ("Unerwarteter Fehler: " + $_.Exception.Message) } catch { Write-Host 'Log nicht schreibbar.' }
    $code = 3
}
finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
exit $code
