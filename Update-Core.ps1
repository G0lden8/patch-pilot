#requires -Version 5.1
<#
=====================================================================
Update-Core  (Patch Pilot 0.10.4, nur Suche + Download, KEINE Installation)
=====================================================================
ZWECK
  Fragt den Windows Update Agent (WUA) nach allen angebotenen, noch nicht
  installierten Updates der von Windows konfigurierten Quelle (WSUS per GPO)
  und laedt fehlende Updates herunter. Bereits geladene werden nicht erneut
  geladen.

ABLAUF
  1. Admin-Pruefung, Schutz gegen Parallelstart (Mutex)
  2. Suche (IsInstalled=0, IsHidden=0), Quelle = Windows-Standard
  3. Lizenz (EULA) der Updates bestaetigen, noetig fuer den Download
  4. Nur fehlende Updates laden, max. $MaxAttempts Versuche
  5. Kontrolle mit frischer lokaler Suche: ist wirklich alles geladen?
     (wie PatchPilot "Download unvollstaendig"; Microsoft-Beispiel
     installiert nur Updates mit IsDownloaded=true)
  6. Ergebnis pruefen, Neustart-Status und Fehler loggen
  Sperrliste (Config\Sperrliste.txt, Update-Blocklist.ps1): gesperrte Updates
  werden in Windows ausgeblendet und nicht geladen.
  Vor der Suche: WSUS laut Registry aktiv? Sonst Ende (Code 8). WSUS nicht
  erreichbar? Dann Netzwerkstatus loggen (Firmennetz erkannt ja/nein, ermittelt
  von Windows: Get-NetConnectionProfile, Kategorie DomainAuthenticated) und
  pruefen, ob vom letzten Download schon Updates bereitliegen (Code 7).
  Jedes Update wird mit allen Eckdaten geloggt (Titel, KB, Typ, Groesse,
  geladen, ID). Warnungen/Fehler zusaetzlich in
  Logs\PatchPilot_Fehler_<Jahr-Monat>.log
  Meldet sich bei Windows Update als 'PatchPilot' (ClientApplicationID), damit
  unsere Vorgaenge im Windows-Updateverlauf erkennbar sind.

VORAUSSETZUNGEN
  Windows 11, PowerShell 5.1, Start als Administrator/SYSTEM.
  WSUS ueber GPO konfiguriert, im Homeoffice per VPN erreichbar.

SICHERHEIT
  Keine Installation, kein Neustart, keine Citrix-Aktion, keine Aenderung
  an WSUS/GPO/Registry. Schreibt nur Logdateien in <Root>\Logs.

PARAMETER
  -Root               Hauptordner (Standard C:\Fernwartung\PatchPilot)
  -MaxAttempts        Download-Versuche (Standard 2)
  -RetryWaitSeconds   Wartezeit zwischen Versuchen (Standard 60)
  -SearchTimeoutSeconds  Hoechstdauer der Suche (Standard 300)
  -WsusCheckSeconds      Schnell-Check des WSUS-Servers (Standard 5)

DATENSCHUTZ
  Geloggt werden nur Updatetitel/KB, Zaehler und Fehlercodes.
  Keine Benutzernamen, keine Pfade aus Benutzerprofilen.

EXITCODES
  0 = alles geladen
  6 = Suche erfolgreich, keine Updates offen (nichts zu tun)
  1 = nicht als Administrator gestartet
  2 = Suche fehlgeschlagen, WSUS nicht erreichbar oder Suche zu langsam
  3 = nichts geladen (Download fehlgeschlagen)
  4 = teilweise geladen (mindestens ein Update fehlt, der Rest ist bereit)
  5 = laeuft bereits (zweite Instanz)
  7 = WSUS nicht erreichbar, aber Updates vom letzten Download liegen bereit
      (lokale Suche, ohne Netzwerk). Update-Run installiert diese ohne WSUS.
  8 = WSUS nicht aktiv (keine WSUS-Adresse oder UseWUServer ungleich 1):
      KEINE Suche, KEIN Download (Regel: Patch Pilot sucht nie ohne WSUS)
=====================================================================
#>
[CmdletBinding()]
param(
    [string]$Root = 'C:\Fernwartung\PatchPilot',
    [int]$MaxAttempts = 2,
    [int]$RetryWaitSeconds = 60,
    [int]$SearchTimeoutSeconds = 300,
    [int]$WsusCheckSeconds = 5
)

$ErrorActionPreference = 'Stop'
$LogDir  = Join-Path $Root 'Logs'
$Month   = Get-Date -Format 'yyyy-MM'
$LogFile = Join-Path $LogDir ('PatchPilot_{0}.log' -f $Month)
$ErrFile = Join-Path $LogDir ('PatchPilot_Fehler_{0}.log' -f $Month)
$LogTag = 'Core'

# Bekannte Fehlercodes -> verstaendlicher Hinweis (keine eigene Diagnose, nur Uebersetzung)
$Hints = @{
    '0x8024200D' = 'Download unvollstaendig oder unbrauchbar, Update muss neu geladen werden (Update-Core erneut ausfuehren)'
    '0x80244010' = 'WSUS nicht erreichbar oder zu viele Anfragen (VPN/Netzwerk pruefen)'
    '0x8024402C' = 'Name des WSUS-Servers nicht aufloesbar (DNS/VPN pruefen)'
    '0x80244022' = 'WSUS antwortet mit Serverfehler (HTTP 503)'
    '0x80072EE7' = 'Servername nicht aufloesbar (DNS/VPN pruefen)'
    '0x80072EFD' = 'Verbindung zum Server nicht moeglich (VPN/Netzwerk pruefen)'
    '0x80072EE2' = 'Zeitueberschreitung bei der Verbindung (VPN/Netzwerk pruefen)'
    '0x8024001E' = 'Dienst wurde beendet (Neustart oder Dienststopp)'
    '0x80240016' = 'Ein anderer Installations- oder Updatevorgang laeuft noch'
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
    return ('{0} | {1} | {2} | Kategorie {3} | max. {4} MB | geladen={5} | Eingabe moeglich={6} | exklusiv={7} | ID {8}' -f
        $U.Title, $kb, $type, $cat, $mb, $U.IsDownloaded, $ib.CanRequestUserInput, $excl, (Get-UpdateKey $U))
}

function Get-HrText([int]$Hr) {
    $hex = '0x{0:X8}' -f $Hr
    if ($Hints.ContainsKey($hex)) { return "$hex - $($Hints[$hex])" }
    return $hex
}

function Get-ResultText([int]$Code) {
    switch ($Code) { 2 { 'ok' } 3 { 'ok mit Fehlern' } 4 { 'fehlgeschlagen' } 5 { 'abgebrochen' } 1 { 'laeuft' } default { 'unbekannt' } }
}

# Netzwerkstatus, wie Windows ihn selbst ermittelt (keine Namen, keine Adressen)
function Write-NetworkStatus {
    try {
        $prof = @(Get-NetConnectionProfile -ErrorAction Stop)
        $dom = @($prof | Where-Object { [string]$_.NetworkCategory -eq 'DomainAuthenticated' }).Count -gt 0
        if ($dom) { Write-Log 'WARN' 'Netzwerk: Firmennetz (Domaene) erkannt: ja -> Netz ist da, WSUS selbst antwortet nicht' }
        else { Write-Log 'WARN' ("Netzwerk: Firmennetz (Domaene) erkannt: nein -> vermutlich kein VPN (Netzwerkverbindungen: {0})" -f $prof.Count) }
    } catch {
        Write-Log 'WARN' ('Netzwerkstatus nicht lesbar: ' + $_.Exception.GetType().Name)
    }
}

# Liegen Updates vom letzten Download bereit? Lokale Suche ohne Netzwerk (so sucht auch Update-Install).
function Get-ReadyCount {
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $session.ClientApplicationID = 'PatchPilot'
        $chk = $session.CreateUpdateSearcher()
        $chk.ServerSelection = 0
        $chk.Online = $false
        $local = $chk.Search('IsInstalled=0 and IsHidden=0')
        $ready = 0
        foreach ($u in $local.Updates) {
            Write-Log 'INFO' ('Lokal bereit: ' + (Get-UpdateInfo $u))
            if ($u.IsDownloaded) { $ready++ }
        }
        return $ready
    } catch {
        Write-Log 'WARN' ('Lokale Suche fehlgeschlagen: ' + (Get-HrText $_.Exception.HResult))
        return 0
    }
}

# Ist der WSUS laut Registry die Quelle? (Adresse eingetragen UND UseWUServer = 1)
function Test-WsusActive {
    $wu = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue
    $au = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -ErrorAction SilentlyContinue
    return ($wu -and $wu.WUServer -and $au -and $au.UseWUServer -eq 1)
}

# Schnell-Check: Ist der per Richtlinie gesetzte WSUS-Server erreichbar? (nur aufrufen, wenn WSUS aktiv)
function Test-WsusReachable {
    $wu = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue
    try {
        $uri = [Uri]$wu.WUServer
        $port = $uri.Port
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($uri.Host, $port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne($WsusCheckSeconds * 1000, $false)
        if ($ok) { try { $client.EndConnect($iar) } catch { $ok = $false } }
        $client.Close()
        if ($ok) { Write-Log 'INFO' "WSUS-Server erreichbar (Port $port)."; return $true }
        Write-Log 'ERROR' "WSUS-Server nicht erreichbar (Port $port, $WsusCheckSeconds s). Moegliche Ursache: kein VPN."
        return $false
    } catch {
        # Datenschutz: keine Fehlermeldung im Klartext (kann Servername/IP enthalten), nur Typ und Code
        Write-Log 'ERROR' ("WSUS-Check fehlgeschlagen: " + $_.Exception.GetType().Name + ", Code 0x" + ('{0:X8}' -f $_.Exception.HResult))
        return $false
    }
}

function Invoke-Main {
    # Phase 1: Admin-Pruefung
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'FEHLER: Bitte als Administrator starten.'
        return 1
    }
    if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    Write-Log 'INFO' 'Update-Core gestartet (Patch Pilot 0.10.4)'

    # Phase 2: WSUS aktiv und erreichbar?
    if (-not (Test-WsusActive)) {
        Write-Log 'ERROR' 'WSUS nicht aktiv (keine WSUS-Adresse oder UseWUServer ungleich 1). Keine Suche, kein Download: Patch Pilot sucht nie ohne WSUS.'
        return 8
    }
    if (-not (Test-WsusReachable)) {
        Write-NetworkStatus
        $ready = Get-ReadyCount
        if ($ready -gt 0) {
            Write-Log 'WARN' "WSUS nicht erreichbar, aber $ready Updates vom letzten Download liegen bereit. Sie koennen ohne WSUS installiert werden."
            return 7
        }
        Write-Log 'INFO' 'Keine geladenen Updates vorhanden.'
        return 2
    }
    # Phase 3: Suche
    try {
        $session  = New-Object -ComObject Microsoft.Update.Session
        $session.ClientApplicationID = 'PatchPilot'   # Kennung im Windows-Updateverlauf (wie im Microsoft-Beispiel)
        $searcher = $session.CreateUpdateSearcher()
        $searcher.ServerSelection = 0   # 0 = Windows-Standard (laut GPO, also WSUS)
        Write-Log 'INFO' 'Phase Suche: Aktion Search(IsInstalled=0 and IsHidden=0)'
        $found = $null
        try { $job = $searcher.BeginSearch('IsInstalled=0 and IsHidden=0', $null, $null) } catch { $job = $null }
        if ($job) {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            while (-not $job.IsCompleted -and $sw.Elapsed.TotalSeconds -lt $SearchTimeoutSeconds) { Start-Sleep -Seconds 2 }
            if (-not $job.IsCompleted) {
                Write-Log 'ERROR' "Suche nach $SearchTimeoutSeconds s abgebrochen (WSUS/Internet zu langsam oder nicht erreichbar). Naechster Schritt: spaeterer Lauf"
                return 2
            }
            $found = $searcher.EndSearch($job)
        } else {
            $found = $searcher.Search('IsInstalled=0 and IsHidden=0')
        }
    } catch {
        $hr = $_.Exception.HResult
        Write-Log 'ERROR' ("Suche fehlgeschlagen: {0}. Naechster Schritt: spaeterer Lauf" -f (Get-HrText $hr))
        return 2
    }

    # Sperrliste: gesperrte Updates in Windows ausblenden und ueberspringen (Update-Blocklist).
    # Nicht mehr gesperrte, von uns ausgeblendete Updates wieder einblenden (erscheinen beim naechsten Lauf).
    $blocked = Set-BlockedHidden $found.Updates
    Add-FeatureSkips $found.Updates $blocked
    Restore-UnblockedUpdates $session 0 $true
    $total = $found.Updates.Count - $blocked.Count
    Write-Log 'INFO' "Gefundene Updates: $total (gesperrt: $($blocked.Count))"
    if ($total -eq 0) {
        Write-Log 'INFO' 'Keine Updates offen. Nichts zu tun. Ende.'
        return 6
    }

    # Phase 3: Fehlende Updates bestimmen
    $need = New-Object -ComObject Microsoft.Update.UpdateColl
    $already = 0
    $onlineKeys = @{}
    foreach ($u in $found.Updates) {
        if ($blocked.ContainsKey(([string]$u.Identity.UpdateID).ToLowerInvariant())) { continue }
        Write-Log 'INFO' ('Update: ' + (Get-UpdateInfo $u))
        $onlineKeys[(Get-UpdateKey $u)] = $true
        if (-not $u.EulaAccepted) { $u.AcceptEula() }
        if ($u.IsDownloaded) { $already++ } else { [void]$need.Add($u) }
    }
    Write-Log 'INFO' "Bereits geladen: $already, noch zu laden: $($need.Count)"

    # Phase 4: Download mit begrenzten Versuchen
    $attempt = 0
    while ($need.Count -gt 0 -and $attempt -lt $MaxAttempts) {
        $attempt++
        Write-Log 'INFO' "Phase Download: Versuch $attempt von $MaxAttempts, Updates: $($need.Count)"
        try {
            $dl = $session.CreateUpdateDownloader()
            $dl.Updates = $need
            $res = $dl.Download()
            Write-Log 'INFO' "Download-Ergebnis: $(Get-ResultText ([int]$res.ResultCode)) (ResultCode $($res.ResultCode)), $(Get-HrText $res.HResult)"
            for ($i = 0; $i -lt $need.Count; $i++) {
                $ur = $res.GetUpdateResult($i)
                if ([int]$ur.ResultCode -ne 2) {
                    Write-Log 'WARN' ("Update '{0}': {1} (ResultCode {2}), {3}" -f $need.Item($i).Title, (Get-ResultText ([int]$ur.ResultCode)), $ur.ResultCode, (Get-HrText $ur.HResult))
                }
            }
        } catch {
            Write-Log 'WARN' ("Download-Aufruf fehlgeschlagen: {0}" -f (Get-HrText $_.Exception.HResult))
        }

        # Nur noch fehlende Updates behalten
        $still = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($u in $need) { if (-not $u.IsDownloaded) { [void]$still.Add($u) } }
        $need = $still

        if ($need.Count -gt 0 -and $attempt -lt $MaxAttempts) {
            Write-Log 'INFO' "Noch $($need.Count) offen, warte $RetryWaitSeconds s"
            Start-Sleep -Seconds $RetryWaitSeconds
        }
    }

    # Phase 5: Kontrolle mit frischer lokaler Suche (so sucht auch Update-Install)
    $verifyMissing = 0
    try {
        $chk = $session.CreateUpdateSearcher()
        $chk.ServerSelection = 0
        $chk.Online = $false
        $local = $chk.Search('IsInstalled=0 and IsHidden=0')
        Write-Log 'INFO' "Kontrolle (lokale Suche): $($local.Updates.Count) Updates"
        foreach ($u in $local.Updates) {
            if ($blocked.ContainsKey(([string]$u.Identity.UpdateID).ToLowerInvariant())) { continue }
            $known = $onlineKeys.ContainsKey((Get-UpdateKey $u))
            if (-not $known) { Write-Log 'WARN' ('Kontrolle: nur lokal gefunden, nicht in der WSUS-Suche: ' + (Get-UpdateInfo $u)) }
            if (-not $u.IsDownloaded) {
                $verifyMissing++
                Write-Log 'WARN' ('Kontrolle: nicht vollstaendig geladen: ' + (Get-UpdateInfo $u))
            }
        }
    } catch {
        Write-Log 'WARN' ("Kontrolle (lokale Suche) fehlgeschlagen: {0}" -f (Get-HrText $_.Exception.HResult))
    }

    # Phase 6: Ergebnis
    $reboot = $false
    try { $reboot = [bool](New-Object -ComObject Microsoft.Update.SystemInfo).RebootRequired } catch { Write-Log 'WARN' 'Neustart-Status nicht lesbar.' }
    Write-Log 'INFO' "Neustart ausstehend (Windows-Status): $reboot"

    if ($need.Count -gt 0) {
        if ($need.Count -lt $total) {
            Write-Log 'WARN' "Teilweise geladen: $($total - $need.Count) von $total bereit, $($need.Count) fehlen. Der Rest ist installierbar, Fehlendes wird spaeter nachgeholt"
            return 4
        }
        Write-Log 'ERROR' "Nichts geladen, $($need.Count) von $total fehlen. Naechster Schritt: spaeterer Lauf"
        return 3
    }
    if ($verifyMissing -gt 0) {
        Write-Log 'WARN' "Download meldet ok, aber die Kontrolle findet $verifyMissing nicht vollstaendig geladene Updates. Teilweise geladen: der Rest ist installierbar, Fehlendes wird spaeter nachgeholt"
        return 4
    }
    Write-Log 'INFO' "Alle $total Updates geladen (Kontrolle bestaetigt). Ende."
    return 0
}

# Sperrliste (gemeinsame Funktionen)
try { . (Join-Path $PSScriptRoot 'Update-Blocklist.ps1') }
catch { Write-Host ('Sperrliste nicht ladbar: ' + $_.Exception.Message); exit 3 }

# Schutz gegen Parallelstart
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Global\PatchPilot_UpdateCore', [ref]$created)
if (-not $created) {
    Write-Host 'Update-Core laeuft bereits. Abbruch.'
    exit 5
}
$code = 0
try { $code = Invoke-Main }
catch { Write-Host ("Unerwarteter Fehler: " + $_.Exception.Message); $code = 3 }
finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
exit $code
