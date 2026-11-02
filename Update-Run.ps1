#requires -Version 5.1
<#
=====================================================================
Update-Run  (Patch Pilot 0.10.4, Ablaufsteuerung, laeuft als SYSTEM per Aufgabenplanung)
=====================================================================
ZWECK
  Steuert den woechentlichen Updateablauf. Windows Update macht die Updates,
  dieses Skript ruft nur die Module in der richtigen Reihenfolge auf:
    Update-Settings Windows-Update-Einstellungen (Registry) ins Log (nur lesen)
    Update-Core    Suche + Download
    Update-User    Dialoge + Citrix-Trennung (ueber Aufgaben im Benutzerkonto)
    Update-Install Installation
    Update-Restart Neustart nur wenn Windows ihn verlangt

MODI
  Preload  Donnerstag: nur Suche + Download, keine Benutzerunterbrechung.
  Auto     Freitag (-Source Poll), Start/Anmeldung des PCs (-Source Boot,
           Anmeldung mit 1 Minute Verzoegerung) und einmalige Erinnerung
           (-Source Remind). Entscheidet selbst anhand des Zustands.
  Manual   Desktop-Button. Zustimmung liegt bereits vor. Nach Erfolg:
           Freitagslauf entfaellt, danach 5 Tage 12 Stunden Updatepause.

ABLAUF Auto
  1. Faelligen Zyklus bestimmen (letzter Freitag ab -FridayHour Uhr).
     Zyklen, deren Freitag in die Pause faellt, werden uebersprungen.
  2. Download (Update-Core). Am Freitag jederzeit, an spaeteren Tagen
     (Nachholen) nur mit angemeldetem Benutzer (ohne Anmeldung kein VPN).
     Keine Updates offen: Zyklus endet still, keine Abfrage.
  3. Erster Updatetag = Tag der ersten Abfrage (Freitag oder, wenn verpasst
     oder der Download erst spaeter klappt, der erste Nachholtag):
     Abfrage 1, bei "Spaeter"/ohne Antwort Abfrage 2 nach 4 Stunden.
     Ab dem Folgetag: Hinweis und Installation ohne neue Abfrage.
     Ohne Benutzersitzung und ohne Citrix: Installation ohne Abfrage.
  4. Citrix trennen und pruefen. Scheitert das: keine Installation.
  5. Installation (Update-Install), danach ggf. Neustart (Update-Restart).
  6. Optional "PC ausschalten": nach dem Neustart faehrt der PC herunter.
  Hoechstens ein Zyklus wird nachgeholt (kein Stapeln verpasster Wochen).
  Fehlerregel (Download, Citrix-Trennung, Installation zaehlen als Versuch):
    Freitag: hoechstens 3 Versuche, Abstand 2 Stunden. Beim ersten Fehler
    des Tages EIN Hinweis (z. B. VPN), weitere Fehler still.
    Danach taeglich nachholen, bis es klappt: hoechstens 2 Versuche pro Tag
    (nach der Anmeldung und 30 Minuten spaeter), still (nur Log).
  IT-Hinweis: Gab es innerhalb von 14 Tagen an mindestens 5 Tagen (mit
    angemeldetem Benutzer) Fehlversuche und keinen erfolgreichen Download,
    erscheint am Ende des Zeitraums EIN Hinweis "Bitte der IT Bescheid sagen".
    Danach beginnt ein neuer Zeitraum. Ein erfolgreicher Download setzt zurueck.
  Einzelne Updates offen (Update-Install 11/12): einmaliges Nachholen am
    Folgetag (neue Suche + Download + Installation). Einzelne Updates mit
    3 Fehlversuchen stellt Update-Install selbst zurueck (dann je Updatelauf
    nur noch 1 Versuch); sie halten den Zyklus nicht offen, kein Hinweis.
  Logs: Logs\PatchPilot_<Jahr-Monat>.log, Warnungen/Fehler zusaetzlich
    in Logs\PatchPilot_Fehler_<Jahr-Monat>.log (12 Monate aufbewahrt).
  Updateverlauf: Bei jedem Start wird der Windows-Updateverlauf seit der
    letzten Pruefung gelesen. Was nicht von unserem Programm (Kennung 'PatchPilot')
    installiert wurde, steht als Warnung im Log und im Fehlerlog. Kein Fenster.
  Einstellungen: Bei jedem Start ruft Update-Run das Modul Update-Settings auf.
    Es loggt die Windows-Update-Werte der Registry (WSUS, Gruppe, Autoupdate,
    Suchhaeufigkeit) beim ersten Lauf des Tages und bei jeder Aenderung.
    Ein Fehler darin haelt den Lauf nie auf.

VORAUSSETZUNGEN
  Windows 11, PowerShell 5.1, Start als SYSTEM/Administrator. Alle Module
  und die Aufgaben PatchPilot-User-* muessen vom Installer angelegt sein.

SICHERHEIT
  Keine eigenen Update-/Download-/Installationsmechanismen. Citrix wird nie
  abgemeldet. Zustandsdatei wird nur von diesem Skript geschrieben.
  Einzelinstanz (Mutex Global\PatchPilot_Run).
  Vor Neustart/Ausschalten werden nur unsere eigenen offenen Fenster
  (Update-Notify, Update-User ausser Citrix-Trennung) beendet (Close-UserPopups).

AENDERUNGEN 0.10.0
  Treiber-Zusatz (Weg 1, Update-Microsoft -Scope Drivers): wichtige Treiber und
  Firmware zusaetzlich direkt bei Windows Update, auch wenn der WSUS nichts
  anbietet. Schalter: Config\Treiber-Aus (Treiber-Ein.bat / Treiber-Aus.bat),
  Standard an. Treiber-Fehler loesen keinen Hinweis und keinen Fehlversuch aus.
  Direktbezug (Weg 2, Update-Microsoft -Scope All): automatisch einmalig, wenn
  der WSUS seit 45 Tagen nicht erreichbar/aktiv ist UND an mindestens 5 Tagen
  Fehlversuche waren (danach wieder normal), oder per Direktbezug-Microsoft.bat.
  WSUS erreichbar, bietet aber seit 45 Tagen nichts an: nur WARN und IT-Hinweis
  (kein automatischer Direktbezug: evtl. bewusst nichts freigegeben).
  Sperrliste Config\Sperrliste.txt fuer alle Wege (Update-Blocklist.ps1).

AENDERUNGEN 0.10.1
  Treiber-Zusatz: Ein Treiber, der schon 3-mal nicht installiert werden konnte,
  loest allein keinen Installationslauf (Abfrage, Citrix-Trennung) mehr aus. Er
  wird weiter mitinstalliert, wenn der WSUS ohnehin Updates bringt (nie aufgeben).
  Treiber-Installationsschritt nur noch, wenn der Download-Schritt Treiber
  bereitgelegt hat (Zustand DrvReady). Vorher suchte er nach der Citrix-Trennung
  jedes Mal bis zu 10 Minuten online, auch wenn es keine Treiber gab.

AENDERUNGEN 0.10.4
  Citrix waehrend der Installation fernhalten (ohne Sperre):
  - Die Citrix-Trennung beendet danach auch die Citrix Workspace-App
    (SelfService.exe -terminate, in Update-User). Ob sie beendet ist, steht im Log.
  - Hinweisfenster "Bitte warten: Citrix bitte nicht starten" (Aufgabe
    PatchPilot-User-Guard) steht waehrend der Installation immer im Vordergrund
    und wird danach beendet.
  - Waechter: Waehrend die Installationsmodule laufen, wird alle 5 Sekunden
    geprueft, ob wieder eine Citrix-Verbindung offen ist. Dann wird sofort
    still neu getrennt (Aufgabe PatchPilot-User-Disconnect), hoechstens 10-mal
    je Installation. Eine Logzeile am Ende fasst zusammen.
  - Direkt vor dem Neustart/Ausschalten wird eine offene Citrix-Verbindung
    noch einmal getrennt.
  - Folgt KEIN Neustart/Ausschalten, startet Patch Pilot die Workspace-App
    wieder (Aufgabe PatchPilot-User-Workspace), wenn sie vorher lief.
  Abschlussmeldung des manuellen Laufs (Done/Partial) ist jetzt ein Fenster mit
  OK in der Mitte (Update-Notify), bleibt stehen bis OK, hoechstens 4 Stunden.
  Mit Neustart weiterhin nur der Windows-Hinweis.

AENDERUNGEN 0.10.3
  Hinweis vor der Installation (Update-User -Action Notice): Standzeit und
  Schliessgrund kommen im Exitcode zurueck (0 = volle Zeit, 1000 + N = nach
  N Sekunden per OK/Taste geschlossen) und werden hier ins Log geschrieben,
  bei weniger als 10 Sekunden als WARN. Vorher stand immer nur "angezeigt".
  Windows-Hinweis "Updates werden geladen und installiert" bekommt einen
  Schliessen-Knopf, damit Windows ihn stehen laesst (Update-Popup).

AENDERUNGEN 0.10.2
  Direktbezug automatisch nur noch, wenn der WSUS eingerichtet, aber nicht
  erreichbar ist (Code 2/98). Ein PC ohne WSUS-Einstellung (Code 8, z. B.
  Test-PC) holt nie von selbst bei Microsoft.
  Schalter Funktionsupdates (Config\Funktionsupdates-Aus, Funktionsupdates-
  Ein.bat / -Aus.bat, Standard an): aus = Funktionsupdates (neue Windows-
  Version) werden auf allen Wegen uebersprungen (nicht ausgeblendet).

AENDERUNGEN 0.9.14
  Weniger Meldungen (Regel: hoechstens eine zur Zeit, nichts doppelt).
  Desktop-Button: ein Status-Hinweis "Updates werden geladen und installiert"
  statt drei; der Citrix-Hinweis ersetzt ihn. Rueckmeldungen am Ende des
  manuellen Laufs nur als Windows-Hinweis. Freitag: Fenster nur noch bei
  Netz/VPN-Fehler und IT-Hinweis, sonst nur Log. Teilfehler und abgelehntes
  Nachholen nur Log. Citrix-Hinweis entfaellt, wenn die Zustimmung weniger
  als 5 Minuten her ist. Kein eigener Neustart-Hinweis mehr (nur Windows),
  kein Abschluss-Hinweis vor dem Ausschalten (Windows-Hinweis genuegt).
  Neu: Start durch die Clientverwaltung ohne Abfrage (-NoAsk, Aufgabe PatchPilot-Fernstart).

AENDERUNGEN 0.9.13
  Eine Versionsnummer fuer alles. Exitcodes im Log als "Nummer = Bedeutung".
  Endzeile je Lauf. Wiederholter Start innerhalb von 10 Minuten ohne Neues:
  nur eine kurze Zeile. Store-App- und Defender-Updates nur gezaehlt.
  Updateverlauf in Ortszeit (Windows liefert UTC). Pausen-Text korrigiert.
  WSUS nicht erreichbar, aber Updates schon geladen: Installation ohne WSUS.
  WSUS nicht aktiv: keine Suche, keine Installation. Netzteil-Abfrage vor
  Firmware-Updates (Update-Power, Update-User -Action Power).

AENDERUNGEN 0.9.12
  Neuer Name Patch Pilot (Ordner, Aufgaben, Logs, Kennung im Updateverlauf;
  alte Kennung WUCtl wird weiter als eigene erkannt). Fenster vor Neustart
  schliessen. Wartezeit fuer den Hinweis vor der Installation 240 s.

PARAMETER
  -Mode          Preload | Auto | Manual
  -Source        Poll | Boot (nur Auto), Standard Boot
  -ShutdownAfter PC nach erfolgreichen Updates ausschalten (nur Manual)
  -Direct        Direktbezug (nur Manual, Aufgabe PatchPilot-Direct, Direktbezug-Microsoft.bat):
                 alle wichtigen Updates direkt bei Windows Update statt WSUS (Update-Microsoft
                 -Scope All), Ablauf wie -NoAsk. Sperrliste gilt.
  -NoAsk         Start durch die Clientverwaltung (nur Manual, Aufgabe PatchPilot-Fernstart): keine Abfrage,
                 die der Benutzer bestaetigen muss. Firmware im Akkubetrieb nur ab 50 % Akku,
                 sonst still auf den naechsten Updatelauf verschoben. Sonst wie der Desktop-Button
                 (Hinweise, Citrix-Hinweis, Pause danach, Neustart mit Windows-Hinweis).
  -Root          Hauptordner (Standard C:\Fernwartung\PatchPilot)
  -FridayHour    Startstunde Freitag (Standard 6)
  -PauseHours    Pause nach manuellem Lauf (Standard 132 = 5 Tage 12 Std.)
  -ReminderHours Abstand zwischen Abfrage 1 und 2 (Standard 4)
  -FridayAttempts / -FridayRetryMinutes  Freitag: Versuche / Abstand (3 / 120)
  -DailyAttempts / -DailyRetryMinutes    Nachholtage: Versuche / Abstand (2 / 30)
  -AlarmWindowDays / -AlarmMinFailDays   IT-Hinweis: Zeitraum / Fehltage (14 / 5)
  -TestReboot        NUR TEST (nur mit -Mode Manual, nur ueber Test-Neustart.bat): Download und
                     Installation werden uebersprungen, es wird ein Neustart simuliert und echt ausgeloest
  -MaxRebootsPer24h  Schutz vor Neustartschleifen (Standard 2 automatische Neustarts je 24 h)
  Jeder Modulaufruf hat eine Zeitgrenze (Core 120, Install 150, Restart 5 Minuten).

DATENSCHUTZ
  Geloggt werden nur Phasen, Zaehler und Exitcodes (Logs\PatchPilot_<Jahr-Monat>.log).
  Zustand: State\state.json (nur Zahlen und Schalter).

EXITCODES
  0 = normal beendet (auch "nichts zu tun" oder "warte auf spaeter")
  1 = nicht als Administrator gestartet
  3 = unerwarteter Fehler
  5 = laeuft bereits (zweite Instanz)
=====================================================================
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Preload','Auto','Manual')][string]$Mode,
    [ValidateSet('Poll','Boot','Remind')][string]$Source = 'Boot',
    [switch]$ShutdownAfter,
    [switch]$NoAsk,
    [switch]$Direct,
    [string]$Root = 'C:\Fernwartung\PatchPilot',
    [ValidateRange(0,23)][int]$FridayHour = 6,
    [int]$PauseHours = 132,
    [int]$ReminderHours = 4,
    [int]$FridayAttempts = 3,
    [int]$FridayRetryMinutes = 120,
    [int]$DailyAttempts = 2,
    [int]$DailyRetryMinutes = 30,
    [int]$AlarmWindowDays = 14,
    [int]$AlarmMinFailDays = 5,
    [int]$MaxRebootsPer24h = 2,
    [switch]$TestReboot
)

$ErrorActionPreference = 'Stop'
$LogDir    = Join-Path $Root 'Logs'
$StateDir  = Join-Path $Root 'State'
$LogFile   = Join-Path $LogDir ('PatchPilot_{0}.log' -f (Get-Date -Format 'yyyy-MM'))
$ErrFile   = Join-Path $LogDir ('PatchPilot_Fehler_{0}.log' -f (Get-Date -Format 'yyyy-MM'))
$LogTag   = 'Run'
$StateFile = Join-Path $StateDir 'state.json'

$ModSettings = 'Update-Settings.ps1'
$ModCore    = 'Update-Core.ps1'
$ModInstall = 'Update-Install.ps1'
$HistoryClientIds = @('PatchPilot', 'WUCtl')   # Kennung unserer Module im Windows-Updateverlauf (WUCtl = alter Name bis V0.9.11)
$ModRestart = 'Update-Restart.ps1'
$ModPower   = 'Update-Power.ps1'
$TaskPower  = 'PatchPilot-User-Power'
$TaskAsk1   = 'PatchPilot-User-Ask1'
$TaskAsk2   = 'PatchPilot-User-Ask2'
$TaskNotice = 'PatchPilot-User-Notice'
$TaskDisc   = 'PatchPilot-User-Disconnect'
$TaskErrNet = 'PatchPilot-User-ErrNet'
$TaskErrFin = 'PatchPilot-User-ErrFinal'
$TaskErrPar = 'PatchPilot-User-ErrPartial'
$TaskErrManNet = 'PatchPilot-User-ErrManNet'
$TaskErrManGen = 'PatchPilot-User-ErrManGen'
$TaskRemind = 'PatchPilot-Remind'
$TaskRunning = 'PatchPilot-User-Running'
$TaskNoOffer = 'PatchPilot-User-ErrNoOffer'
$ModMs      = 'Update-Microsoft.ps1'
$DriversOffFile = Join-Path $Root 'Config\Treiber-Aus'   # vorhanden = Treiber-Zusatz aus (Standard: an)
$DirectDays = 45          # Direktbezug: so viele Tage ohne erfolgreichen WSUS-Kontakt ...
$DirectMinFailDays = 5    # ... und an mindestens so vielen Tagen Fehlversuche
$NoOfferDays = 45         # WSUS erreichbar, bietet aber so lange nichts an: WARN + IT-Hinweis
$script:UseMicrosoft = $false   # dieser Lauf holt alles direkt bei Windows Update (Direktbezug)
$TaskDone    = 'PatchPilot-User-Done'
$TaskGuard   = 'PatchPilot-User-Guard'       # ab 0.10.4: Hinweis "Citrix bitte nicht starten" waehrend der Installation
$TaskWorkspace = 'PatchPilot-User-Workspace' # ab 0.10.4: Workspace-App wieder starten, wenn kein Neustart folgt
$WatchMaxDisconnects = 10   # Waechter: hoechstens so viele erneute Trennungen je Installation
$NoticeSkipSec = 300   # Citrix-Hinweis entfaellt, wenn die Zustimmung (Abfrage) weniger als 5 Minuten her ist
$PsExe      = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

$script:Due = $null
$script:DueKey = 0
$script:NoUpdates = $false
$script:Buffer = $null      # gesammelte INFO-Zeilen bei schnellem Wiederholungsstart
$script:LastInfo = ''       # letzte INFO-Meldung (Zusammenfassung des Laufs)
$script:RepeatMin = 0
$script:CitrixWatch = $false   # Waechter aktiv (nur waehrend der Installationsmodule)
$script:WatchCount = 0         # erneute Trennungen in dieser Installation
$script:GuardOn = $false       # Hinweisfenster "Citrix bitte nicht starten" gestartet
$script:WsWasOpen = $false     # Workspace-App lief vor der Trennung
$script:PowerAction = $false   # Neustart oder Ausschalten wurde von Windows angenommen

# Bedeutung eines Exitcodes (nur dieser eine Code wird ins Log geschrieben)
function Get-CodeText([string]$What, $Code) {
    if ($null -eq $Code -or "$Code" -eq '') { return 'keine Rueckmeldung (Zeitueberschreitung)' }
    $c = [int]$Code
    if ($What -eq 'Notice' -and $c -ge 1000) { return ("$c = nach " + ($c - 1000) + " Sekunden per OK oder Taste geschlossen") }
    $common = @{ 97 = 'kein Exitcode erhalten'; 98 = 'Zeitgrenze ueberschritten, abgebrochen'; 99 = 'Modul fehlt' }
    $t = switch ($What) {
        'Core'     { @{ 0 = 'alle Updates geladen'; 1 = 'nicht als Administrator gestartet'; 2 = 'Suche fehlgeschlagen'; 3 = 'nichts geladen'; 4 = 'teilweise geladen'; 5 = 'laeuft bereits'; 6 = 'keine Updates offen'; 7 = 'WSUS nicht erreichbar, Updates aber schon geladen'; 8 = 'WSUS nicht aktiv, nichts gesucht' } }
        'Install'  { @{ 0 = 'fertig, kein Neustart noetig'; 1 = 'nicht als Administrator gestartet'; 2 = 'lokale Suche fehlgeschlagen'; 3 = 'Installation nicht moeglich'; 4 = 'Windows Update belegt'; 5 = 'laeuft bereits'; 8 = 'WSUS nicht aktiv, nichts installiert'; 10 = 'fertig, Neustart noetig'; 11 = 'Teilerfolg, Neustart noetig'; 12 = 'Teilerfolg' } }
        'MsDownload' { @{ 0 = 'alles geladen'; 1 = 'nicht als Administrator gestartet'; 2 = 'Suche bei Windows Update fehlgeschlagen'; 3 = 'nichts geladen'; 4 = 'teilweise geladen'; 5 = 'laeuft bereits'; 6 = 'nichts gefunden'; 7 = 'nur zurueckgestellte Treiber'; 9 = 'Windows Update per Richtlinie gesperrt' } }
        'MsInstall'  { @{ 0 = 'fertig, kein Neustart noetig'; 1 = 'nicht als Administrator gestartet'; 2 = 'Suche bei Windows Update fehlgeschlagen'; 3 = 'Installation nicht moeglich'; 4 = 'Windows Update belegt'; 5 = 'laeuft bereits'; 9 = 'Windows Update per Richtlinie gesperrt'; 10 = 'fertig, Neustart noetig'; 11 = 'Teilerfolg, Neustart noetig'; 12 = 'Teilerfolg' } }
        'Restart'  { @{ 0 = 'kein Neustart noetig'; 20 = 'Neustart geplant'; 21 = 'Neustart noetig'; 1 = 'nicht als Administrator gestartet'; 3 = 'shutdown.exe fehlgeschlagen'; 5 = 'laeuft bereits' } }
        'Settings' { @{ 0 = 'ok'; 1 = 'nicht als Administrator gestartet'; 3 = 'Fehler beim Lesen' } }
        'Power'    { @{ 0 = 'keine Abfrage noetig'; 30 = 'Firmware, Akkubetrieb, Akku mindestens 50 %'; 31 = 'Firmware, Akkubetrieb, Akku unter 50 %'; 1 = 'nicht als Administrator gestartet'; 2 = 'Pruefung nicht moeglich' } }
        'PowerAsk' { @{ 0 = 'Ja, Moment'; 1 = 'Nein, ohne Netzteil'; 6 = 'Spaeter'; 3 = 'keine Antwort'; 2 = 'Fenster nicht anzeigbar'; 5 = 'verfallen' } }
        'Ask'      { @{ 0 = 'Ja'; 4 = 'Ja, danach ausschalten'; 1 = 'Spaeter'; 3 = 'keine Antwort'; 2 = 'Fenster nicht anzeigbar'; 5 = 'verfallen' } }
        'Notice'   { @{ 0 = 'angezeigt (volle Zeit)'; 2 = 'Fenster nicht anzeigbar'; 5 = 'verfallen' } }
        'Workspace' { @{ 0 = 'gestartet'; 10 = 'lief bereits'; 11 = 'Start fehlgeschlagen'; 13 = 'SelfService.exe nicht gefunden'; 2 = 'Fehler' } }
        'Citrix'   { @{ 0 = 'getrennt und geprueft'; 10 = 'keine Citrix-Verbindung'; 11 = 'Befehl fehlgeschlagen'; 12 = 'Citrix noch aktiv'; 13 = 'SelfService.exe nicht gefunden'; 2 = 'Fehler' } }
        'Shutdown' { @{ 0 = 'angenommen'; 1190 = 'anderes Herunterfahren laeuft bereits' } }
        'Run'      { @{ 0 = 'normal beendet'; 1 = 'nicht als Administrator gestartet'; 3 = 'unerwarteter Fehler'; 5 = 'laeuft bereits' } }
        default    { @{} }
    }
    if ($t.ContainsKey($c)) { return "$c = $($t[$c])" }
    if ($common.ContainsKey($c)) { return "$c = $($common[$c])" }
    return "$c = unbekannt"
}
function Add-LogLine([string]$Path, [string]$Line) {
    # Gemeinsame Datei fuer alle Teile. Schreiben andere gerade, kurz warten und erneut versuchen.
    for ($try = 1; $try -le 10; $try++) {
        try { Add-Content -LiteralPath $Path -Value $Line -Encoding UTF8 -ErrorAction Stop; return } catch { Start-Sleep -Milliseconds (Get-Random -Minimum 50 -Maximum 300) }
    }
}

function Write-Log([string]$Level, [string]$Msg) {
    $line = '{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $LogTag, $Msg
    if ($Level -eq 'INFO') { $script:LastInfo = $Msg }
    if ($null -ne $script:Buffer) {
        if ($Level -eq 'INFO') { [void]$script:Buffer.Add($line); Write-Host $line; return }
        Stop-LogBuffer
    }
    Add-LogLine $LogFile $line
    if ($Level -eq 'WARN' -or $Level -eq 'ERROR') { Add-LogLine $ErrFile $line }
    Write-Host $line
}

# Gesammelte Zeilen doch schreiben (sobald etwas passiert, das ins Log gehoert)
function Stop-LogBuffer {
    if ($null -eq $script:Buffer) { return }
    $b = $script:Buffer; $script:Buffer = $null
    foreach ($l in $b) { Add-LogLine $LogFile $l }
}

# ---------------- Zustand (nur Zahlen/Schalter, atomar geschrieben) ----------------
function New-State {
    [pscustomobject]@{
        DoneCycle = 0; Cycle = 0; PauseUntil = 0
        Downloaded = $false
        FirstAskAt = 0; Round2Done = $false
        Consent = $false; AutoConsent = $false
        ShutdownAfter = $false; ShutdownPending = $false
        AttemptDay = 0; DayAttempts = 0; LastFailAt = 0; ErrShownDay = 0
        AlarmStart = 0; AlarmDays = 0; AlarmLastDay = 0
        RebootCount = 0; RebootWindowStart = 0
        ShutdownBootId = ''; ShutdownSetAt = 0; ShutdownTries = 0
        Partial = $false; FollowUp = $false; FollowDay = 0; FollowDone = $false
        LastHistoryDate = ''
        LastRunEnd = 0; LastRunSummary = ''
        ConsentAt = 0
        DirectCycle = 0; WsusOkAt = 0; WsusFailDays = 0; WsusFailLastDay = 0; WsusOfferAt = 0
        DrvReady = $false
    }
}

function Read-State {
    $d = New-State
    if (Test-Path -LiteralPath $StateFile) {
        try {
            $s = Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $d.PSObject.Properties) {
                $src = $s.PSObject.Properties[$p.Name]
                if ($null -ne $src -and $null -ne $src.Value) { $p.Value = $src.Value }
            }
        } catch {
            Write-Log 'WARN' 'Zustandsdatei unlesbar, wird als .bad beiseite gelegt und neu begonnen.'
            try { Move-Item -LiteralPath $StateFile -Destination ($StateFile + '.bad') -Force } catch { Write-Log 'WARN' 'Zustandsdatei konnte nicht umbenannt werden.' }
            $d = New-State
        }
    }
    return $d
}

function Save-State($s) {
    $tmp = $StateFile + '.tmp'
    [IO.File]::WriteAllText($tmp, ($s | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $StateFile) { [IO.File]::Replace($tmp, $StateFile, [NullString]::Value) }
    else { [IO.File]::Move($tmp, $StateFile) }
}

# ---------------- Windows-Updateverlauf ----------------
# Prueft, ob seit der letzten Pruefung Updates OHNE unser Programm installiert wurden
# (z. B. durch Windows' eigene automatische Updates oder manuell ueber die Einstellungen).
# Vorbild: PSWindowsUpdate Get-WUHistory (QueryHistory der offiziellen Windows-Update-Schnittstelle).
# Unsere Module melden sich als 'PatchPilot'. Nur lesen, kein Netzwerk. Fehler halten den Lauf nie auf.
function Write-ForeignHistory($st) {
    try {
        $session  = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $count = [int]$searcher.GetTotalHistoryCount()
        $ci = [Globalization.CultureInfo]::InvariantCulture
        $since = $null
        if ($st.LastHistoryDate) {
            try { $since = [datetime]::ParseExact([string]$st.LastHistoryDate, 'yyyy-MM-ddTHH:mm:ss', $ci) } catch { $since = $null }
        }
        if (-not $since) {
            $since = (Get-Date).AddDays(-8)
            Write-Log 'INFO' 'Updateverlauf: erste Pruefung, Rueckblick 8 Tage.'
        }
        $newest = $since; $foreign = 0; $defender = 0; $store = 0
        if ($count -gt 0) {
            foreach ($h in $searcher.QueryHistory(0, $count)) {
                # Windows liefert die Zeit in UTC (Weltzeit): in Ortszeit umrechnen
                $d = [DateTime]::SpecifyKind([datetime]$h.Date, [DateTimeKind]::Utc).ToLocalTime()
                if ($d -le $since) { continue }
                if ($d -gt $newest) { $newest = $d }
                $op = [int]$h.Operation
                if ($op -ne 1 -and $op -ne 2) { continue }
                if ($HistoryClientIds -contains [string]$h.ClientApplicationID) { continue }
                $title = [string]$h.Title
                # Defender-Definitionen (KB2267602) und -Plattform (KB4052623) kommen ueber Defender selbst: nur zaehlen
                if ($title -match 'KB2267602|KB4052623') { $defender++; continue }
                # Microsoft-Store-Apps (z. B. WindowsAppRuntime) installiert der Store selbst: nur zaehlen
                if ([string]$h.ClientApplicationID -like 'Acquisition*' -or $title -match '^[0-9A-Z]{12}-') { $store++; continue }
                $foreign++
                $what = 'installiert'; if ($op -eq 2) { $what = 'deinstalliert' }
                $res = switch ([int]$h.ResultCode) { 2 { 'ok' } 3 { 'ok mit Fehlern' } 4 { 'fehlgeschlagen' } 5 { 'abgebrochen' } default { 'unbekannt' } }
                Write-Log 'WARN' ("Ohne unser Programm {0}: {1} | Ergebnis: {2} | Programm '{3}' | Zeit {4}" -f
                    $what, $title, $res, [string]$h.ClientApplicationID, $d.ToString('yyyy-MM-dd HH:mm', $ci))
            }
        }
        if ($defender -gt 0 -or $store -gt 0) { Write-Log 'INFO' "Updateverlauf: $defender Defender-Updates und $store Store-App-Updates ohne unser Programm (normal, nur gezaehlt)." }
        if ($foreign -eq 0) { Write-Log 'INFO' 'Updateverlauf: seit der letzten Pruefung keine Windows-Updates ohne unser Programm installiert.' }
        else { Write-Log 'WARN' "Updateverlauf: $foreign Vorgaenge ohne unser Programm seit der letzten Pruefung (Details oben)." }
        $st.LastHistoryDate = $newest.ToString('yyyy-MM-ddTHH:mm:ss', $ci)
        Save-State $st
    } catch {
        Write-Log 'WARN' ('Updateverlauf nicht lesbar: ' + $_.Exception.Message)
    }
}

# ---------------- Zeit ----------------
function Get-DueFriday([datetime]$Now) {
    $d = $Now.Date
    $back = (([int]$d.DayOfWeek) - 5 + 7) % 7
    $f = $d.AddDays(-$back).AddHours($FridayHour)
    if ($f -gt $Now) { $f = $f.AddDays(-7) }
    return $f
}
function Get-Epoch { return [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
function Get-Today { return [int](Get-Date -Format 'yyyyMMdd') }
# Faelliger Freitag selbst? (Freitag ab Startstunde bis Mitternacht)
function Test-DueDay { return ((Get-Date).Date -eq $script:Due.Date) }
# Kennung des aktuellen Systemstarts (Startzeit). Aendert sich nur durch einen echten Neustart.
function Get-BootId {
    try { return (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('yyyyMMddHHmmss') } catch { return '' }
}
function ConvertFrom-Epoch([long]$E) { return [DateTimeOffset]::FromUnixTimeSeconds($E).LocalDateTime }

# ---------------- Sitzung / Module / Benutzeraufgaben ----------------
function Test-UserSession {
    return (@(Get-Process -Name explorer -ErrorAction SilentlyContinue).Count -gt 0)
}
function Test-CitrixProcess {
    $names = @('SelfService','wfica32','CDViewer','Citrix.DesktopViewer.App')
    return (@(Get-Process -ErrorAction SilentlyContinue | Where-Object { $names -contains $_.ProcessName }).Count -gt 0)
}

# Ab 0.10.4: offene Citrix-Verbindung (Sitzungsprozesse, egal in welcher Sitzung; pro PC nur ein Benutzer)
function Test-CitrixSession {
    $names = @('wfica32','CDViewer','Citrix.DesktopViewer.App')
    return (@(Get-Process -ErrorAction SilentlyContinue | Where-Object { $names -contains $_.ProcessName }).Count -gt 0)
}
# Ab 0.10.4: Workspace-App laeuft (Fenster mit den Verbindungen / Symbol neben der Uhr)
function Test-WorkspaceProcess {
    $names = @('SelfService','Receiver')
    return (@(Get-Process -ErrorAction SilentlyContinue | Where-Object { $names -contains $_.ProcessName }).Count -gt 0)
}

# Ab 0.10.4, Waechter: wird waehrend eines Installationsmoduls alle 5 Sekunden aufgerufen.
# Ist wieder eine Citrix-Verbindung offen, startet er die Trennung (gleiche Aufgabe wie vor der
# Installation, ohne zu warten). Laeuft die Trennung noch, wird nichts doppelt gestartet.
function Invoke-CitrixWatch {
    if (-not (Test-CitrixSession)) { return }
    if ($script:WatchCount -ge $WatchMaxDisconnects) { return }
    try {
        $t = Get-ScheduledTask -TaskPath '\' -TaskName $TaskDisc -ErrorAction Stop
        if ($t.State -eq 'Running') { return }
        Start-ScheduledTask -InputObject $t | Out-Null
        $script:WatchCount++
        if ($script:WatchCount -eq $WatchMaxDisconnects) {
            Write-Log 'WARN' "Waechter: Citrix wurde $WatchMaxDisconnects-mal neu verbunden. Keine weitere Trennung in dieser Installation."
        }
    } catch {
        $script:WatchCount = $WatchMaxDisconnects
        Write-Log 'WARN' ('Waechter: Citrix-Trennung nicht startbar: ' + $_.Exception.Message)
    }
}

# Ab 0.10.4: Hinweisfenster "Citrix bitte nicht starten" starten (ohne Warten).
function Start-CitrixGuard {
    $script:WatchCount = 0
    $script:CitrixWatch = $true
    try {
        Start-ScheduledTask -TaskPath '\' -TaskName $TaskGuard -ErrorAction Stop | Out-Null
        $script:GuardOn = $true
        Write-Log 'INFO' 'Hinweis "Citrix bitte nicht starten" angezeigt, Waechter aktiv.'
    } catch {
        Write-Log 'WARN' ('Hinweis "Citrix bitte nicht starten" nicht startbar: ' + $_.Exception.Message + '. Waechter trotzdem aktiv.')
    }
}

# Ab 0.10.4: Waechter aus, Hinweisfenster beenden, Ergebnis in einer Zeile. Mehrfacher Aufruf ist unschaedlich.
function Stop-CitrixGuard {
    if ($script:CitrixWatch) {
        $script:CitrixWatch = $false
        if ($script:WatchCount -gt 0) {
            Write-Log 'WARN' "Citrix waehrend der Installation $($script:WatchCount)-mal neu verbunden, jeweils automatisch getrennt."
        } else {
            Write-Log 'INFO' 'Waechter: keine neue Citrix-Verbindung waehrend der Installation.'
        }
    }
    if ($script:GuardOn) {
        $script:GuardOn = $false
        try { Stop-ScheduledTask -TaskPath '\' -TaskName $TaskGuard -ErrorAction Stop | Out-Null }
        catch { Write-Log 'WARN' ('Hinweis "Citrix bitte nicht starten" nicht beendbar: ' + $_.Exception.Message) }
    }
}

# Ab 0.10.4: direkt vor Neustart/Ausschalten eine offene Citrix-Verbindung noch einmal trennen.
function Invoke-DisconnectBeforePower {
    if (-not (Test-UserSession) -or -not (Test-CitrixSession)) { return }
    $r = Invoke-UserTask $TaskDisc 90
    Write-Log 'INFO' ("Citrix-Trennung vor Neustart/Ausschalten: " + (Get-CodeText 'Citrix' $r))
}

# Ab 0.10.4: nach der Installation ohne Neustart/Ausschalten die Workspace-App wieder starten,
# wenn sie vor der Trennung lief und jetzt nicht mehr laeuft.
function Restore-Workspace {
    if (-not $script:WsWasOpen) { return }
    $script:WsWasOpen = $false
    if ($script:PowerAction) { return }   # Neustart/Ausschalten: Windows startet die App danach selbst
    if (Test-WorkspaceProcess) { return }
    if (-not (Test-UserSession)) { return }
    $r = Invoke-UserTask $TaskWorkspace 60
    Write-Log 'INFO' ("Workspace-App wieder gestartet (kein Neustart): " + (Get-CodeText 'Workspace' $r))
}

function Invoke-Module([string]$File, [string[]]$ModArgs = @(), [int]$TimeoutMin = 150, [switch]$NoFlush) {
    if (-not $NoFlush) { Stop-LogBuffer }
    $path = Join-Path $Root $File
    if (-not (Test-Path -LiteralPath $path)) { Write-Log 'ERROR' "Modul fehlt: $File"; return 99 }
    $argList = @('-NoProfile', '-ExecutionPolicy', 'RemoteSigned', '-File', ('"{0}"' -f $path)) + $ModArgs
    $p = Start-Process -FilePath $PsExe -ArgumentList $argList -PassThru -NoNewWindow
    $null = $p.Handle   # Handle festhalten, sonst ist ExitCode in Windows PowerShell 5.1 leer
    # In 5-Sekunden-Schritten warten (ab 0.10.4), damit der Citrix-Waechter waehrend der Installation pruefen kann
    $limit = [Diagnostics.Stopwatch]::StartNew()
    $done = $false
    while (-not $done -and $limit.Elapsed.TotalMinutes -lt $TimeoutMin) {
        $done = $p.WaitForExit(5000)
        if (-not $done -and $script:CitrixWatch) { Invoke-CitrixWatch }
    }
    if (-not $done) {
        Write-Log 'ERROR' "Modul $File nach $TimeoutMin Minuten abgebrochen (Zeitgrenze)."
        try { & (Join-Path $env:SystemRoot 'System32\taskkill.exe') /PID $p.Id /T /F | Out-Null } catch { Write-Log 'WARN' ("Modul $File konnte nicht beendet werden: " + $_.Exception.Message) }
        $p.Dispose()
        return 98
    }
    $rc = $p.ExitCode
    $p.Dispose()
    if ($null -eq $rc -or "$rc" -eq '') { Write-Log 'ERROR' "Modul $File lieferte keinen Exitcode."; return 97 }
    return [int]$rc
}

# Neustart-Schutz: hoechstens $MaxRebootsPer24h automatische Neustarts innerhalb von 24 Stunden.
function Test-RebootAllowed($st) {
    $now = Get-Epoch
    if ($st.RebootWindowStart -le 0 -or ($now - [long]$st.RebootWindowStart) -gt 86400) { $st.RebootWindowStart = $now; $st.RebootCount = 0; Save-State $st }
    if ($st.RebootCount -ge $MaxRebootsPer24h) {
        Write-Log 'ERROR' "Neustart-Sperre: bereits $($st.RebootCount) automatische Neustarts in 24 Stunden. Kein weiterer Neustart (Schutz vor Neustartschleife)."
        return $false
    }
    return $true
}
function Add-RebootCount($st) { $st.RebootCount = $st.RebootCount + 1; Save-State $st }

# Startet eine feste Aufgabe im Benutzerkonto und liefert deren Exitcode (oder $null bei Zeitueberschreitung).
function Invoke-UserTask([string]$Name, [int]$TimeoutSec) {
    Stop-LogBuffer
    try {
        $t = Get-ScheduledTask -TaskPath '\' -TaskName $Name -ErrorAction Stop
        $before = (Get-ScheduledTaskInfo -InputObject $t).LastRunTime
        Start-ScheduledTask -InputObject $t | Out-Null
    } catch {
        Write-Log 'ERROR' ("Benutzeraufgabe $Name nicht startbar: " + $_.Exception.Message)
        return $null
    }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $seenRunning = $false
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        Start-Sleep -Seconds 2
        $t = Get-ScheduledTask -TaskPath '\' -TaskName $Name
        $info = Get-ScheduledTaskInfo -InputObject $t
        if ($t.State -eq 'Running') { $seenRunning = $true; continue }
        if ($seenRunning -or $info.LastRunTime -gt $before) { return [int]$info.LastTaskResult }
    }
    Write-Log 'WARN' "Benutzeraufgabe ${Name}: Zeitueberschreitung, wird beendet."
    try { Stop-ScheduledTask -TaskPath '\' -TaskName $Name | Out-Null } catch { Write-Log 'WARN' ("Benutzeraufgabe $Name nicht beendbar: " + $_.Exception.Message) }
    return $null
}

# Vor Neustart/Ausschalten: unsere eigenen offenen Fenster (Update-Notify, Update-User) schliessen,
# damit die Windows-Meldung allein auf dem Bildschirm steht. Erkennung nur ueber den Skriptnamen in
# der Befehlszeile. Die Citrix-Trennung (-Action Disconnect) wird nie beendet, fremde Programme nie.
function Close-UserPopups {
    try {
        $own = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop | Where-Object {
            $_.CommandLine -match 'Update-(Notify|User)(_V[0-9.]+)?\.ps1' -and $_.CommandLine -notmatch '-Action\s+Disconnect' })
        foreach ($p in $own) {
            try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop } catch { Write-Log 'WARN' ("Fenster nicht schliessbar (PID $($p.ProcessId)): " + $_.Exception.Message) }
        }
        if ($own.Count -gt 0) { Write-Log 'INFO' "Offene Fenster vor Neustart/Ausschalten geschlossen: $($own.Count)" }
    } catch {
        Write-Log 'WARN' ('Offene Fenster nicht pruefbar: ' + $_.Exception.Message)
    }
}

# ---------------- Zyklus ----------------
function Initialize-Cycle($st) {
    if ($st.Cycle -ne $script:DueKey) {
        $st.Cycle = $script:DueKey
        $st.Downloaded = $false; $st.FirstAskAt = 0; $st.Round2Done = $false
        $st.Consent = $false; $st.AutoConsent = $false; $st.ShutdownAfter = $false
        $st.AttemptDay = 0; $st.DayAttempts = 0; $st.LastFailAt = 0
        $st.Partial = $false; $st.FollowUp = $false; $st.FollowDay = 0; $st.FollowDone = $false
        $st.DirectCycle = 0
        Write-Log 'INFO' "Neuer Zyklus $($script:DueKey)"
        Save-State $st
    }
}

function Close-Cycle($st, [string]$Result) {
    if ($st.DoneCycle -lt $script:DueKey) { $st.DoneCycle = $script:DueKey }
    $st.Consent = $false; $st.AutoConsent = $false; $st.Downloaded = $false
    $st.FirstAskAt = 0; $st.Round2Done = $false
    $st.AttemptDay = 0; $st.DayAttempts = 0; $st.LastFailAt = 0
    $st.Partial = $false; $st.FollowUp = $false; $st.FollowDay = 0; $st.FollowDone = $false
    $st.DirectCycle = 0
    $ok = ($Result -eq 'Installed' -or $Result -eq 'NoUpdates')
    if (-not $ok) { $st.ShutdownAfter = $false }
    if ($ok -and $Mode -eq 'Manual' -and -not $TestReboot) {
        $st.PauseUntil = (Get-Epoch) + ([long]$PauseHours * 3600)
        Write-Log 'INFO' ("Pause bis " + (ConvertFrom-Epoch $st.PauseUntil).ToString('yyyy-MM-dd HH:mm'))
    }
    Write-Log 'INFO' "Zyklus $($script:DueKey) abgeschlossen: $Result"
    Save-State $st
}

function Get-AttemptGate($st) {
    if ($Mode -eq 'Manual') { return 'Go' }
    $limit = $DailyAttempts; $gap = $DailyRetryMinutes
    if (Test-DueDay) { $limit = $FridayAttempts; $gap = $FridayRetryMinutes }
    $used = 0
    if ($st.AttemptDay -eq (Get-Today)) { $used = $st.DayAttempts }
    if ($used -ge $limit) { return 'DayDone' }
    if ($st.LastFailAt -gt 0 -and ((Get-Epoch) - [long]$st.LastFailAt) -lt ([long]$gap * 60)) { return 'Wait' }
    return 'Go'
}

# Hinweis fuer den Benutzer, ohne Warten.
# Fenster (Net, Final) nur, wenn der Benutzer etwas tun kann bzw. die IT Bescheid wissen muss.
# Rueckmeldungen zum manuellen Lauf: Running und Manual* sind Windows-Hinweise unten rechts, Done und Partial (ab 0.10.4) ein Fenster mit OK.
function Send-ErrorNotice($st, [string]$Kind) {
    $today = [int](Get-Date -Format 'yyyyMMdd')
    $name = $null
    switch ($Kind) {
        'Net'           { $name = $TaskErrNet }
        'Final'         { $name = $TaskErrFin }
        'NoOffer'       { $name = $TaskNoOffer }
        'Partial'       { $name = $TaskErrPar }
        'ManualNet'     { $name = $TaskErrManNet }
        'ManualGeneric' { $name = $TaskErrManGen }
        'Running'       { $name = $TaskRunning }
        'Done'          { $name = $TaskDone }
    }
    if (-not $name) { Write-Log 'WARN' "Unbekannte Hinweisart '$Kind', nichts angezeigt."; return }
    # Hoechstens ein Netz-Fehlerfenster pro Tag. Alle anderen Arten sind Einzelereignisse.
    $status = ($Kind -ne 'Net')
    if (-not $status -and $st.ErrShownDay -eq $today) { Write-Log 'INFO' 'Fehlerhinweis heute schon gezeigt, kein weiterer.'; return }
    if (-not (Test-UserSession)) { return }
    Stop-LogBuffer
    try {
        Start-ScheduledTask -TaskPath '\' -TaskName $name | Out-Null
        if (-not $status) { $st.ErrShownDay = $today; Save-State $st }
        Write-Log 'INFO' "Hinweis an Benutzer gestartet: $Kind"
    } catch {
        Write-Log 'WARN' ("Fehlerhinweis nicht startbar ($Kind): " + $_.Exception.Message)
    }
}

# Zaehlt einen fehlgeschlagenen Versuch und beendet den Zyklus, wenn die Fehlerregel erschoepft ist.
# Setzt den einmaligen Zeitpunkt der festen Aufgabe PatchPilot-Remind (kein Dauer-Takt, keine neue Aufgabe).
function Set-Reminder([int]$Minutes) {
    if ($Mode -eq 'Manual') { return }
    $at = (Get-Date).AddMinutes($Minutes)
    if ($at -ge (Get-Date).Date.AddDays(1)) { Write-Log 'INFO' 'Erinnerung faellt nach Mitternacht: naechster Versuch nach der Anmeldung.'; return }
    try {
        $trg = New-ScheduledTaskTrigger -Once -At $at
        Set-ScheduledTask -TaskPath '\' -TaskName $TaskRemind -Trigger $trg | Out-Null
        Write-Log 'INFO' ("Naechster Lauf geplant: " + $at.ToString('yyyy-MM-dd HH:mm'))
    } catch {
        Write-Log 'WARN' ("Erinnerung nicht setzbar: " + $_.Exception.Message)
    }
}

# Teilergebnis: einmaliges Nachholen am Folgetag mit Abfrage (Ablehnen erlaubt).
function Start-FollowUp($st, [string]$Why) {
    $st.FollowUp = $true; $st.FollowDone = $false; $st.FollowDay = [int](Get-Date -Format 'yyyyMMdd')
    $st.Partial = $false; $st.Downloaded = $false; $st.Consent = $false; $st.AutoConsent = $false
    $st.FirstAskAt = 0; $st.Round2Done = $false
    $st.AttemptDay = 0; $st.DayAttempts = 0; $st.LastFailAt = 0; $st.ShutdownAfter = $false
    Save-State $st
    Write-Log 'WARN' "$Why. Nachholen am Folgetag mit Abfrage vorgemerkt."
}

function Invoke-FollowUp($st) {
    $today = [int](Get-Date -Format 'yyyyMMdd')
    if ($today -le $st.FollowDay) { Write-Log 'INFO' 'Nachholen erst ab dem Folgetag. Ende.'; return }
    if (Test-UserSession) {
        Invoke-Ask $st 1
        if (-not $st.Consent) {
            if ($st.FirstAskAt -eq 0) { return }
            # Benutzer hat selbst abgelehnt: kein weiteres Fenster direkt danach (nur Log).
            Close-Cycle $st 'Partial'
            Write-Log 'INFO' 'Nachholen abgelehnt. Naechster Versuch beim naechsten Updatelauf.'
            return
        }
    } elseif (Test-CitrixProcess) {
        Write-Log 'WARN' 'Citrix-Prozesse ohne Benutzersitzung. Nachholen wartet.'
        return
    } else {
        $st.Consent = $true; $st.AutoConsent = $true
    }
    $st.FollowUp = $false; $st.FollowDone = $true; Save-State $st
    Write-Log 'INFO' 'Nachholen freigegeben.'
    if (-not $st.Downloaded -and -not (Step-Download $st)) { return }
    Invoke-InstallPath $st
}

# IT-Hinweis-Zaehler: erfolgreicher Download setzt zurueck.
function Reset-Alarm($st) {
    if ($st.AlarmStart -ne 0 -or $st.AlarmDays -ne 0) { $st.AlarmStart = 0; $st.AlarmDays = 0; $st.AlarmLastDay = 0; Save-State $st }
}

# Zaehlt einen Fehltag (nur mit angemeldetem Benutzer) und meldet am Ende des Zeitraums ggf. die IT-Bitte.
# Liefert $true, wenn der IT-Hinweis gezeigt wurde (dann kein weiteres Fenster in diesem Lauf).
function Update-Alarm($st) {
    if (-not (Test-UserSession)) { return $false }
    $today = Get-Today
    if ($st.AlarmStart -eq 0) { $st.AlarmStart = $today; $st.AlarmDays = 0; $st.AlarmLastDay = 0 }
    if ($st.AlarmLastDay -ne $today) { $st.AlarmDays = $st.AlarmDays + 1; $st.AlarmLastDay = $today }
    Save-State $st
    $start = [datetime]::ParseExact([string]$st.AlarmStart, 'yyyyMMdd', $null)
    $endDay = [int]$start.AddDays($AlarmWindowDays - 1).ToString('yyyyMMdd')
    Write-Log 'INFO' ("Fehltage im Zeitraum seit " + $start.ToString('yyyy-MM-dd') + ": $($st.AlarmDays) (Hinweis ab $AlarmMinFailDays am Ende von $AlarmWindowDays Tagen)")
    if ($today -lt $endDay) { return $false }
    $shown = $false
    if ($st.AlarmDays -ge $AlarmMinFailDays) {
        Write-Log 'ERROR' "Seit $AlarmWindowDays Tagen an $($st.AlarmDays) Tagen keine Updates geladen. IT-Hinweis an Benutzer."
        Send-ErrorNotice $st 'Final'
        $shown = $true
    }
    # Neuer Zeitraum ab morgen (naechster Fehltag startet ihn)
    $st.AlarmStart = 0; $st.AlarmDays = 0; $st.AlarmLastDay = 0; Save-State $st
    return $shown
}

function Register-Failure($st, [string]$Kind, [string]$Why) {
    $today = Get-Today
    $dueDay = Test-DueDay
    if ($Mode -ne 'Manual') {
        if ($st.AttemptDay -ne $today) { $st.AttemptDay = $today; $st.DayAttempts = 0 }
        $st.DayAttempts = $st.DayAttempts + 1
    }
    $st.LastFailAt = Get-Epoch
    Save-State $st
    $limit = $DailyAttempts; $gap = $DailyRetryMinutes
    if ($dueDay) { $limit = $FridayAttempts; $gap = $FridayRetryMinutes }
    if ($Mode -eq 'Manual') { Write-Log 'ERROR' "$Why (manueller Lauf)" }
    else { Write-Log 'ERROR' "$Why (Versuch $($st.DayAttempts) von $limit heute)" }
    $itShown = Update-Alarm $st
    # Manueller Lauf: immer kurze Rueckmeldung (Windows-Hinweis), ohne Versprechen eines automatischen Versuchs.
    # Freitag: Fenster nur bei Netz-Fehler (Benutzer kann VPN verbinden), hoechstens eines pro Tag.
    # Allgemeine Fehler: nur Log (Benutzer kann nichts tun, IT-Hinweis nach 14 Tagen bleibt).
    if (-not $itShown -and $Mode -eq 'Manual') { Send-ErrorNotice $st ('Manual' + $Kind); return }
    if ($Mode -eq 'Manual') { return }
    if (-not $itShown -and $dueDay -and $Kind -eq 'Net') { Send-ErrorNotice $st 'Net' }
    if ($st.DayAttempts -lt $limit) { Set-Reminder $gap }
    else { Write-Log 'INFO' 'Heute keine weiteren Versuche. Naechster Versuch morgen nach der Anmeldung.' }
}

# ---------------- Microsoft direkt (Treiber-Zusatz und Direktbezug, Modul Update-Microsoft) ----------------
function Test-DriversOn { return -not (Test-Path -LiteralPath $DriversOffFile) }

# Merkt sich den WSUS-Kontakt fuer die 45-Tage-Regeln (nur nach einem Update-Core-Lauf).
function Update-WsusCounters($st, $rc) {
    $now = Get-Epoch
    $today = Get-Today
    if ($st.WsusOkAt -le 0) { $st.WsusOkAt = $now }        # Zaehlung beginnt mit dem ersten Lauf
    if ($st.WsusOfferAt -le 0) { $st.WsusOfferAt = $now }
    if ($rc -eq 0 -or $rc -eq 4 -or $rc -eq 6) { $st.WsusOkAt = $now; $st.WsusFailDays = 0; $st.WsusFailLastDay = 0 }
    if ($rc -eq 0 -or $rc -eq 4) { $st.WsusOfferAt = $now }
    # Code 8 (WSUS absichtlich nicht eingerichtet) zaehlt nicht: dort nie automatisch Direktbezug (ab 0.10.2)
    if ($rc -eq 2 -or $rc -eq 7 -or $rc -eq 98) {
        if ($st.WsusFailLastDay -ne $today) { $st.WsusFailDays = $st.WsusFailDays + 1; $st.WsusFailLastDay = $today }
    }
    Save-State $st
}

function Get-DaysSince([long]$Epoch) { return [int][math]::Floor(((Get-Epoch) - $Epoch) / 86400) }

# Direktbezug faellig? Nur im automatischen Lauf: 45 Tage ohne WSUS-Kontakt UND an mind. 5 Tagen Fehlversuche.
function Test-DirectDue($st) {
    if ($Mode -ne 'Auto' -or $st.WsusOkAt -le 0) { return $false }
    $days = Get-DaysSince $st.WsusOkAt
    return ($days -ge $DirectDays -and $st.WsusFailDays -ge $DirectMinFailDays)
}

# Direktbezug fuer diesen Updatelauf einschalten. Die 45-Tage-Zaehlung beginnt neu (danach wieder normal).
function Start-DirectMode($st, [string]$Why) {
    $script:UseMicrosoft = $true
    $st.DirectCycle = $script:DueKey
    $st.WsusOkAt = Get-Epoch; $st.WsusFailDays = 0; $st.WsusFailLastDay = 0
    Save-State $st
    Write-Log 'WARN' "Direktbezug bei Microsoft fuer diesen Updatelauf: $Why"
}

# WSUS erreichbar, bietet aber seit 45 Tagen nichts an: nur Warnung und IT-Hinweis, kein Direktbezug.
function Test-NoOffer($st) {
    if ($st.WsusOfferAt -le 0) { return }
    $days = Get-DaysSince $st.WsusOfferAt
    if ($days -lt $NoOfferDays) { return }
    Write-Log 'WARN' "WSUS ist erreichbar, bietet aber seit $days Tagen keine Updates an. Kein automatischer Direktbezug (evtl. bewusst nichts freigegeben). IT-Hinweis."
    if (Test-UserSession) {
        Send-ErrorNotice $st 'NoOffer'
        $st.WsusOfferAt = Get-Epoch; Save-State $st   # naechster Hinweis fruehestens nach weiteren 45 Tagen
    }
}

# Treiber-Zusatz: wichtige Treiber/Firmware bei Windows Update laden. Liefert $true, wenn welche bereitliegen.
# Fehler hier sind nie ein Fehlversuch und loesen keinen Hinweis aus (nur Log).
# Merkt sich im Zustand (DrvReady), ob Treiber bereitliegen: nur dann laeuft spaeter der Treiber-Installationsschritt.
function Step-DriverDownload($st) {
    $ready = $false
    if (Test-DriversOn) {
        Write-Log 'INFO' 'Phase Download: Treiber-Zusatz (Update-Microsoft -Scope Drivers)'
        $drc = Invoke-Module $ModMs @('-Scope', 'Drivers', '-Action', 'Download') 60
        Write-Log 'INFO' ("Treiber-Zusatz Download Exitcode: " + (Get-CodeText 'MsDownload' $drc))
        $ready = ($drc -eq 0 -or $drc -eq 4)
        # 7 = nur Treiber mit 3 Fehlversuchen: kein eigener Installationslauf, aber mitinstallieren, wenn WSUS etwas bringt
        $st.DrvReady = ($ready -or $drc -eq 7)
    } else { $st.DrvReady = $false }
    Save-State $st
    return $ready
}

# Direktbezug: alles Wichtige bei Windows Update laden (statt Update-Core).
function Step-DownloadMicrosoft($st) {
    Write-Log 'INFO' 'Phase Download: Direktbezug (Update-Microsoft -Scope All)'
    $rc = Invoke-Module $ModMs @('-Scope', 'All', '-Action', 'Download') 120
    Write-Log 'INFO' ("Direktbezug Download Exitcode: " + (Get-CodeText 'MsDownload' $rc))
    if ($rc -eq 0) { Reset-Alarm $st; $st.Downloaded = $true; Save-State $st; return $true }
    if ($rc -eq 4) { Reset-Alarm $st; $st.Downloaded = $true; $st.Partial = $true; Save-State $st; Write-Log 'WARN' 'Teilweise geladen: es wird installiert, was bereit ist.'; return $true }
    if ($rc -eq 6) { $script:NoUpdates = $true; return $false }
    if ($rc -eq 5) {
        if ($Mode -eq 'Manual') { Write-Log 'WARN' 'Windows Update belegt (manueller Lauf).'; Send-ErrorNotice $st 'ManualGeneric' }
        return $false
    }
    if ($rc -eq 9) { Register-Failure $st 'Generic' 'Direktbezug nicht moeglich: Windows Update per Gruppenrichtlinie gesperrt'; return $false }
    Register-Failure $st 'Net' ("Direktbezug: Suche/Download bei Microsoft fehlgeschlagen (" + (Get-CodeText 'MsDownload' $rc) + "), moegliche Ursache: kein Internet")
    return $false
}

function Step-Download($st) {
    if ($script:UseMicrosoft) { return (Step-DownloadMicrosoft $st) }
    Write-Log 'INFO' 'Phase Download: Update-Core'
    $rc = Invoke-Module $ModCore @() 120
    Write-Log 'INFO' ("Update-Core Exitcode: " + (Get-CodeText 'Core' $rc))
    Update-WsusCounters $st $rc
    if ($rc -eq 0 -or $rc -eq 4 -or $rc -eq 6) { Reset-Alarm $st }
    # WSUS seit 45 Tagen nicht erreichbar und an mind. 5 Tagen Fehlversuche: einmalig Direktbezug
    if (($rc -eq 2 -or $rc -eq 98) -and (Test-DirectDue $st)) {
        Start-DirectMode $st ("WSUS seit " + (Get-DaysSince $st.WsusOkAt) + " Tagen ohne Kontakt, Fehlversuche an $($st.WsusFailDays) Tagen")
        return (Step-DownloadMicrosoft $st)
    }
    # Treiber-Zusatz (nur wenn der WSUS-Teil geklappt hat oder Geladenes bereitliegt)
    $drvReady = $false
    if ($rc -eq 0 -or $rc -eq 4 -or $rc -eq 6 -or $rc -eq 7) { $drvReady = Step-DriverDownload $st }
    if ($rc -eq 7) {
        # WSUS nicht erreichbar, aber vom letzten Download liegt alles bereit: ohne WSUS installieren.
        # Zaehlt trotzdem als Fehltag (WSUS fehlt), damit dauerhafte Probleme zum IT-Hinweis fuehren.
        $null = Update-Alarm $st
        $st.Downloaded = $true; Save-State $st
        Write-Log 'WARN' 'WSUS nicht erreichbar: es werden die bereits geladenen Updates installiert.'
        return $true
    }
    if ($rc -eq 8) { Register-Failure $st 'Generic' 'WSUS nicht aktiv (Einstellung): keine Suche, keine Installation'; return $false }
    if ($rc -eq 6) {
        Test-NoOffer $st
        if ($drvReady) {
            $st.Downloaded = $true; Save-State $st
            Write-Log 'INFO' 'WSUS bietet nichts an, Treiber von Windows Update liegen bereit: diese werden installiert.'
            return $true
        }
        $script:NoUpdates = $true; return $false
    }
    if ($rc -eq 0) { $st.Downloaded = $true; Save-State $st; return $true }
    if ($rc -eq 4) { $st.Downloaded = $true; $st.Partial = $true; Save-State $st; Write-Log 'WARN' 'Teilweise geladen: es wird installiert, was bereit ist.'; return $true }
    if ($rc -eq 5) {
        # Windows Update belegt: kein Fehlversuch. Manueller Lauf braucht trotzdem eine Rueckmeldung (Status-Hinweis ersetzen).
        if ($Mode -eq 'Manual') { Write-Log 'WARN' 'Windows Update belegt (manueller Lauf).'; Send-ErrorNotice $st 'ManualGeneric' }
        return $false
    }
    if ($rc -eq 2 -or $rc -eq 3 -or $rc -eq 98) { Register-Failure $st 'Net' ("Suche/Download fehlgeschlagen (" + (Get-CodeText 'Core' $rc) + "), moegliche Ursache: kein VPN oder WSUS nicht erreichbar") }
    else { Register-Failure $st 'Generic' ("Update-Core Fehler (" + (Get-CodeText 'Core' $rc) + ")") }
    return $false
}

# Keine Updates offen: Zyklus still beenden. Beim manuellen Lauf "Fertig" melden und ggf. ausschalten.
function Complete-NoUpdates($st) {
    Write-Log 'INFO' 'Keine Updates offen.'
    Close-Cycle $st 'NoUpdates'
    if ($Mode -ne 'Manual') { return }
    if ($st.ShutdownAfter) {
        $st.ShutdownAfter = $false; Save-State $st
        Close-UserPopups
        # Kein eigener Abschluss-Hinweis: der Windows-Hinweis zum Ausschalten genuegt (nichts doppelt).
        $null = Invoke-ShutdownNow
        return
    }
    Send-ErrorNotice $st 'Done'
}

function Invoke-ShutdownNow {
    Invoke-DisconnectBeforePower
    Write-Log 'INFO' 'Phase Ausschalten: shutdown /s /t 60'
    & (Join-Path $env:SystemRoot 'System32\shutdown.exe') /s /f /t 60 /c 'Der Computer wird in 60 Sekunden ausgeschaltet. Bitte speichern Sie Ihre Arbeit.' /d p:2:17
    $rc = $LASTEXITCODE
    Write-Log 'INFO' ("shutdown.exe Exitcode: " + (Get-CodeText 'Shutdown' $rc))
    if ($rc -eq 0) { $script:PowerAction = $true }
    return [int]$rc
}

# Ausschalten nach dem Neustart vormerken, zusammen mit der Kennung des aktuellen Systemstarts.
function Set-ShutdownPending($st) {
    $st.ShutdownPending = $true; $st.ShutdownAfter = $false
    $st.ShutdownBootId = Get-BootId; $st.ShutdownSetAt = Get-Epoch; $st.ShutdownTries = 0
    Save-State $st
}
function Clear-ShutdownPending($st) {
    $st.ShutdownPending = $false; $st.ShutdownBootId = ''; $st.ShutdownSetAt = 0; $st.ShutdownTries = 0
    Save-State $st
}

# Nach dem Neustart: vorgemerktes Ausschalten ausfuehren. Vormerkung bleibt, bis Windows das Ausschalten annimmt.
function Invoke-PendingShutdown($st) {
    Write-Log 'INFO' 'Ausschalten nach Updates vorgemerkt.'
    if ($st.ShutdownBootId -and $st.ShutdownBootId -eq (Get-BootId)) {
        if (((Get-Epoch) - [long]$st.ShutdownSetAt) -gt 1800) {
            Write-Log 'ERROR' 'Der vorgemerkte Neustart hat innerhalb von 30 Minuten nicht stattgefunden. Ausschalten wird verworfen.'
            Clear-ShutdownPending $st
            return
        }
        Write-Log 'INFO' 'Noch derselbe Systemstart: Neustart steht aus. Ausschalten erst nach dem Neustart.'
        return
    }
    $rr = Invoke-Module $ModRestart @('-DryRun') 5
    if ($rr -eq 21 -or $rr -eq 0) { Close-UserPopups }
    if ($rr -eq 21) {
        if (Test-RebootAllowed $st) {
            $rr = Invoke-Module $ModRestart @() 5
            if ($rr -eq 20) {
                Add-RebootCount $st
                $st.ShutdownBootId = Get-BootId; $st.ShutdownSetAt = Get-Epoch; Save-State $st
                Write-Log 'INFO' 'Windows verlangt noch einen Neustart. Ausschalten folgt danach.'
            }
        }
        return
    }
    if ($rr -ne 0) { Write-Log 'WARN' ("Update-Restart Exitcode: " + (Get-CodeText 'Restart' $rr) + ". Ausschalten wird beim naechsten PC-Start erneut versucht."); return }
    $src = Invoke-ShutdownNow
    if ($src -eq 0) { Clear-ShutdownPending $st; return }
    $st.ShutdownTries = $st.ShutdownTries + 1; Save-State $st
    if ($st.ShutdownTries -ge 3) {
        Write-Log 'ERROR' 'Ausschalten dreimal abgelehnt. Vormerkung wird verworfen.'
        Clear-ShutdownPending $st
    } else {
        Write-Log 'WARN' "Ausschalten abgelehnt (Code $src). Neuer Versuch beim naechsten PC-Start."
    }
}

# Installation einschliesslich Citrix-Trennung und Neustart/Ausschalten.
# Netzteil-Regel vor Firmware-Updates. Liefert $true, wenn Firmware diesmal ausgelassen wird.
# Regel: Firmware nur mit Netzteil oder Akku mindestens 50 %. Im Akkubetrieb wird der Benutzer gefragt.
function Get-SkipFirmware($userPresent) {
    if ($TestReboot) { return $false }
    $pc = Invoke-Module $ModPower @() 3
    Write-Log 'INFO' ("Update-Power Exitcode: " + (Get-CodeText 'Power' $pc))
    if ($pc -ne 30 -and $pc -ne 31) { return $false }
    # Fernstart (-NoAsk): keine Abfrage. Ab 50 % Akku installieren, darunter verschieben (siehe unten).
    if ($NoAsk) { Write-Log 'INFO' 'Netzteil-Abfrage entfaellt (Start durch die Clientverwaltung).' }
    if ($userPresent -and -not $NoAsk) {
        $a = Invoke-UserTask $TaskPower 480   # 120 s Abfrage + bis 5 min Warten + Puffer
        Write-Log 'INFO' ("Netzteil-Abfrage: " + (Get-CodeText 'PowerAsk' $a))
        if ($a -ne 0 -and $a -ne 1) { Write-Log 'WARN' 'Firmware diesmal nicht installiert (Spaeter oder keine Antwort). Naechster Updatelauf.'; return $true }
        $pc = Invoke-Module $ModPower @() 3
        Write-Log 'INFO' ("Update-Power Exitcode (nach Abfrage): " + (Get-CodeText 'Power' $pc))
    }
    if ($pc -eq 31) { Write-Log 'WARN' 'Firmware diesmal nicht installiert: Akkubetrieb und Akku unter 50 %. Naechster Updatelauf.'; return $true }
    return $false
}

# Ab 0.10.4: Rahmen um die Installation. Was auch passiert (auch bei Fehler oder vorzeitigem Ende):
# Waechter aus, Hinweisfenster zu, Workspace-App wieder starten, wenn kein Neustart folgt.
function Invoke-InstallPath($st) {
    $script:CitrixWatch = $false; $script:WatchCount = 0; $script:GuardOn = $false
    $script:WsWasOpen = $false; $script:PowerAction = $false
    try { Invoke-InstallPathCore $st }
    finally {
        Stop-CitrixGuard
        try { Restore-Workspace } catch { Write-Log 'WARN' ('Workspace-App nicht wieder startbar: ' + $_.Exception.Message) }
    }
}

function Invoke-InstallPathCore($st) {
    $userPresent = Test-UserSession
    $skipFw = Get-SkipFirmware $userPresent
    if ($userPresent) {
        # Hinweis vor der Citrix-Trennung. Entfaellt nur, wenn der Benutzer in der Abfrage gerade eben
        # (weniger als 5 Minuten) zugestimmt hat: die Abfrage nennt die Citrix-Trennung bereits (nichts doppelt).
        # Liegt mehr Zeit dazwischen (z. B. Download), kommt der Hinweis (Schutz vor "Citrix ohne Vorwarnung").
        # Beim manuellen Lauf immer zeigen (ersetzt dort den Status-Hinweis).
        $age = -1
        if ($st.ConsentAt -gt 0) { $age = (Get-Epoch) - [long]$st.ConsentAt }
        if ($Mode -ne 'Manual' -and -not $st.AutoConsent -and $age -ge 0 -and $age -lt $NoticeSkipSec) {
            Write-Log 'INFO' "Hinweis vor der Installation: entfaellt (Zustimmung vor $age Sekunden)"
        } else {
            $r = Invoke-UserTask $TaskNotice 120
            Write-Log 'INFO' ("Hinweis vor der Installation: " + (Get-CodeText 'Notice' $r))
            if ($null -ne $r -and [int]$r -ge 1000 -and ([int]$r - 1000) -lt 10) {
                Write-Log 'WARN' ("Hinweis vor der Installation nur " + ([int]$r - 1000) + " Sekunden gesehen (vorzeitig geschlossen). Die Citrix-Warnung wurde evtl. nicht gelesen.")
            }
        }
        $script:WsWasOpen = Test-WorkspaceProcess
        $r = Invoke-UserTask $TaskDisc 180
        Write-Log 'INFO' ("Citrix-Trennung: " + (Get-CodeText 'Citrix' $r))
        if ($r -ne 0 -and $r -ne 10) {
            Register-Failure $st 'Generic' ("Citrix-Trennung nicht erfolgreich (" + (Get-CodeText 'Citrix' $r) + "), keine Installation")
            return
        }
        if ($script:WsWasOpen) {
            if (Test-WorkspaceProcess) { Write-Log 'WARN' 'Workspace-App laeuft nach der Trennung noch (Citrix-Befehl -terminate ohne Wirkung).' }
            else { Write-Log 'INFO' 'Workspace-App beendet.' }
        }
        Start-CitrixGuard
    } elseif (Test-CitrixProcess) {
        Write-Log 'WARN' 'Citrix-Prozesse ohne Benutzersitzung gefunden. Keine Installation. Naechster Schritt: spaeterer Lauf'
        return
    }

    if ($TestReboot) { $rc = 10; Write-Log 'WARN' 'TESTMODUS: Installation simuliert (Exitcode 10 = fertig, Neustart noetig).' }
    elseif ($script:UseMicrosoft) {
        Write-Log 'INFO' 'Phase Installation: Direktbezug (Update-Microsoft -Scope All)'
        $iargs = @('-Scope', 'All', '-Action', 'Install', '-Cycle', [string]$st.Cycle); if ($skipFw) { $iargs += '-SkipFirmware' }
        $rc = Invoke-Module $ModMs $iargs 150
        Write-Log 'INFO' ("Direktbezug Install Exitcode: " + (Get-CodeText 'MsInstall' $rc))
        if ($rc -eq 2 -or $rc -eq 9) { $rc = 3 }   # Suche/Richtlinie: wie "Installation nicht moeglich" behandeln
    } else {
        Write-Log 'INFO' 'Phase Installation: Update-Install'
        $iargs = @('-Cycle', [string]$st.Cycle); if ($skipFw) { $iargs += '-SkipFirmware' }
        $rc = Invoke-Module $ModInstall $iargs 150
        Write-Log 'INFO' ("Update-Install Exitcode: " + (Get-CodeText 'Install' $rc))
        # Treiber-Zusatz in derselben Installation (ein Citrix-Hinweis, hoechstens ein Neustart).
        # Sein Ergebnis zaehlt nur fuer den Neustart: Treiber-Fehler sind kein Teilfehler und loesen keinen Hinweis aus.
        # Nur wenn der Download-Schritt Treiber bereitgelegt hat (sonst unnoetige Online-Suche nach der Citrix-Trennung).
        if ((Test-DriversOn) -and $st.DrvReady -and ($rc -eq 0 -or $rc -eq 10 -or $rc -eq 11 -or $rc -eq 12)) {
            Write-Log 'INFO' 'Phase Installation: Treiber-Zusatz (Update-Microsoft -Scope Drivers)'
            $dargs = @('-Scope', 'Drivers', '-Action', 'Install', '-Cycle', [string]$st.Cycle); if ($skipFw) { $dargs += '-SkipFirmware' }
            $drc = Invoke-Module $ModMs $dargs 90
            Write-Log 'INFO' ("Treiber-Zusatz Install Exitcode: " + (Get-CodeText 'MsInstall' $drc))
            if ($drc -eq 10 -or $drc -eq 11) {
                if ($rc -eq 0) { $rc = 10 } elseif ($rc -eq 12) { $rc = 11 }
            }
            $st.DrvReady = $false; Save-State $st
        } elseif ((Test-DriversOn) -and ($rc -eq 0 -or $rc -eq 10 -or $rc -eq 11 -or $rc -eq 12)) {
            Write-Log 'INFO' 'Treiber-Zusatz: keine Treiber bereitgelegt, Installationsschritt entfaellt.'
        }
    }
    $reboot = ($rc -eq 10 -or $rc -eq 11)
    # Installation vorbei: Waechter aus, Hinweisfenster zu (vor allen weiteren Meldungen)
    Stop-CitrixGuard

    if ($rc -eq 0 -or $rc -eq 10 -or $rc -eq 11 -or $rc -eq 12) {
        # Offene Updates meldet nur Update-Install (zaehlt auch nicht Geladenes, stellt nach 3 Fehlversuchen zurueck)
        $partial = ($rc -eq 11 -or $rc -eq 12)
        if ($partial -and $Mode -ne 'Manual' -and -not $st.FollowDone) {
            Start-FollowUp $st 'Updates unvollstaendig (Fehler bei einzelnen Updates)'
        } else {
            Close-Cycle $st 'Installed'
            if ($reboot -or $st.ShutdownAfter) { Close-UserPopups }
            # Rueckmeldung nur beim manuellen Lauf. Kein eigener Hinweis bei Neustart oder Ausschalten
            # (dort kommt der Windows-Hinweis). Automatischer Teilfehler: nur Log.
            if ($Mode -eq 'Manual' -and -not $reboot -and -not $st.ShutdownAfter) {
                if ($partial) { Send-ErrorNotice $st 'Partial' } else { Send-ErrorNotice $st 'Done' }
            } elseif ($partial) { Write-Log 'WARN' 'Updates unvollstaendig. Naechster Versuch beim naechsten Updatelauf.' }
            if ($st.ShutdownAfter) {
                if ($reboot) {
                    Set-ShutdownPending $st
                } else {
                    $st.ShutdownAfter = $false; Save-State $st
                    $null = Invoke-ShutdownNow
                    return
                }
            }
        }
    } elseif ($rc -eq 4 -or $rc -eq 5) {
        Write-Log 'WARN' 'Windows Update belegt. Naechster Schritt: spaeterer Lauf (kein Fehlversuch gezaehlt)'
        if ($Mode -eq 'Manual') { Send-ErrorNotice $st 'ManualGeneric' }
    } else {
        $st.Downloaded = $false
        Register-Failure $st 'Generic' ("Installation nicht vollstaendig (" + (Get-CodeText 'Install' $rc) + "), Download wird wiederholt")
    }

    if ($reboot -and ($TestReboot -or (Test-RebootAllowed $st))) {
        Invoke-DisconnectBeforePower
        Write-Log 'INFO' 'Phase Neustart: Update-Restart'
        $rargs = @(); if ($TestReboot) { $rargs = @('-ForceTest') }
        $rr = Invoke-Module $ModRestart $rargs 5
        Write-Log 'INFO' ("Update-Restart Exitcode: " + (Get-CodeText 'Restart' $rr))
        if ($rr -eq 20) { $script:PowerAction = $true }
        if ($rr -eq 20 -and -not $TestReboot) { Add-RebootCount $st }
    }
}

function Invoke-Ask($st, [int]$Which) {
    if ($Which -eq 1) { $name = $TaskAsk1; $timeout = 30 * 60 + 180 } else { $name = $TaskAsk2; $timeout = 60 * 60 + 180 }
    if ($Which -eq 1) { $st.FirstAskAt = Get-Epoch } else { $st.Round2Done = $true }
    Save-State $st
    Write-Log 'INFO' "Phase Abfrage $Which"
    $rc = Invoke-UserTask $name $timeout
    Write-Log 'INFO' ("Abfrage ${Which}: " + (Get-CodeText 'Ask' $rc))
    if ($null -eq $rc -or $rc -eq 2) {
        # Fenster vermutlich nicht gezeigt: Abfrage beim naechsten Lauf wiederholen
        if ($Which -eq 1) { $st.FirstAskAt = 0 } else { $st.Round2Done = $false }
        Save-State $st
        return
    }
    if ($rc -eq 0 -or $rc -eq 4) {
        $st.Consent = $true; $st.ConsentAt = Get-Epoch
        if ($rc -eq 4) { $st.ShutdownAfter = $true }
        Save-State $st
    }
}

# ---------------- Hauptablauf ----------------
function Invoke-Main {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'FEHLER: Bitte als Administrator starten.'
        return 1
    }
    foreach ($d in @($LogDir, $StateDir)) { if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }
    Write-Log 'INFO' "Update-Run gestartet (Patch Pilot 0.10.4, Modus $Mode, Quelle $Source)"
    if ($TestReboot -and $Mode -ne 'Manual') { Write-Log 'ERROR' '-TestReboot ist nur mit -Mode Manual erlaubt.'; return 3 }
    if ($NoAsk -and $Mode -ne 'Manual') { Write-Log 'ERROR' '-NoAsk ist nur mit -Mode Manual erlaubt.'; return 3 }
    if ($TestReboot) { Write-Log 'WARN' 'TESTMODUS: kein Download, keine Installation. Neustart wird simuliert und ausgeloest.' }
    try {
        # Monatsdateien nach 12 Monaten loeschen, alte Tagesdateien (frueheres Format) nach 30 Tagen
        Get-ChildItem -LiteralPath $LogDir -Filter 'PatchPilot_*.log' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddMonths(-12) } | Remove-Item -Force -ErrorAction SilentlyContinue
        Get-ChildItem -LiteralPath $LogDir -Filter 'Update*_*.log' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | Remove-Item -Force -ErrorAction SilentlyContinue
    } catch { Write-Log 'WARN' ('Alte Logs nicht loeschbar: ' + $_.Exception.Message) }

    $st = Read-State
    # Schneller Wiederholungsstart (z. B. PC-Start + Anmeldung kurz hintereinander): INFO-Zeilen erst sammeln.
    # Passiert nichts Neues, steht am Ende nur eine kurze Zeile im Log.
    if ($Mode -eq 'Auto' -and $st.LastRunEnd -gt 0) {
        $ago = (Get-Epoch) - [long]$st.LastRunEnd
        if ($ago -ge 0 -and $ago -lt 600) { $script:RepeatMin = [int][math]::Floor($ago / 60); $script:Buffer = New-Object System.Collections.ArrayList }
    }
    if (-not $TestReboot) { Write-ForeignHistory $st }
    # Windows-Update-Einstellungen protokollieren (eigenes Modul, nur lesen, haelt den Lauf nie auf)
    if (-not $TestReboot) {
        $rcSettings = Invoke-Module $ModSettings @() 2 -NoFlush
        if ($rcSettings -ne 0) { Write-Log 'WARN' ("Update-Settings Exitcode: " + (Get-CodeText 'Settings' $rcSettings) + " (Einstellungen nicht vollstaendig geloggt)") }
    }
    $now = Get-Date
    $script:Due = Get-DueFriday $now
    $script:DueKey = [int]$script:Due.ToString('yyyyMMdd')
    if ($Direct -and $Mode -ne 'Manual') { Write-Log 'ERROR' '-Direct ist nur mit -Mode Manual erlaubt.'; return 3 }
    if ($Mode -ne 'Preload' -and $st.DirectCycle -gt 0 -and $st.DirectCycle -eq $script:DueKey) {
        $script:UseMicrosoft = $true
        Write-Log 'INFO' 'Direktbezug bei Microsoft ist fuer diesen Updatelauf aktiv.'
    }
    $pauseEnd = $null
    if ($st.PauseUntil -gt 0) { $pauseEnd = ConvertFrom-Epoch $st.PauseUntil }

    # ---- Donnerstag: nur vorladen ----
    if ($Mode -eq 'Preload') {
        if ($now.DayOfWeek -ne [DayOfWeek]::Thursday) { Write-Log 'INFO' 'Vorladen nur am Donnerstag. Ende.'; return 0 }
        $nextFriday = $script:Due.AddDays(7)
        if ($pauseEnd -and ($now -lt $pauseEnd -or $nextFriday -lt $pauseEnd)) {
            Write-Log 'INFO' 'Pause aktiv, der naechste Freitag entfaellt. Kein Vorladen.'
            return 0
        }
        $rc = Invoke-Module $ModCore
        Write-Log 'INFO' ("Vorladen beendet, Update-Core Exitcode: " + (Get-CodeText 'Core' $rc))
        if ($rc -eq 0 -or $rc -eq 4 -or $rc -eq 6 -or $rc -eq 7) { $null = Step-DriverDownload $st }
        return 0
    }

    # ---- Nach Neustart: ggf. ausschalten ----
    if ($Mode -eq 'Auto' -and $Source -eq 'Boot' -and $st.ShutdownPending) {
        Invoke-PendingShutdown $st
        return 0
    }

    # ---- Manueller Lauf ----
    if ($Mode -eq 'Manual') {
        Initialize-Cycle $st
        $st.Consent = $true; $st.AutoConsent = $false; $st.Downloaded = $false
        $st.LastFailAt = 0
        $st.Partial = $false; $st.FollowUp = $false; $st.FollowDay = 0; $st.FollowDone = $false
        $st.ShutdownAfter = [bool]$ShutdownAfter
        Save-State $st
        $who = 'Benutzer'; if ($NoAsk) { $who = 'Clientverwaltung, ohne Abfrage' }
        if ($Direct) { $who = 'Administrator, Direktbezug bei Microsoft, ohne Abfrage'; Start-DirectMode $st 'Start durch Administrator (Direktbezug-Microsoft.bat)' }
        Write-Log 'INFO' "Manueller Start durch $who (Ausschalten danach: $([bool]$ShutdownAfter))"
        Send-ErrorNotice $st 'Running'
        if (-not $TestReboot -and -not (Step-Download $st)) {
            if ($script:NoUpdates) { Complete-NoUpdates $st; return 0 }
            Write-Log 'ERROR' 'Download nicht vollstaendig. Manueller Lauf beendet. Naechster Schritt: Button erneut nutzen, sonst naechster regulaerer Lauf'
            return 0
        }
        Invoke-InstallPath $st
        return 0
    }

    # ---- Automatischer Zyklus ----
    if ($pauseEnd -and $script:Due -lt $pauseEnd) {
        if ($st.DoneCycle -lt $script:DueKey) {
            $st.DoneCycle = $script:DueKey; Save-State $st
            Write-Log 'INFO' "Zyklus $($script:DueKey) faellt in die Pause nach manuellem Lauf und entfaellt."
        }
        if ($now -lt $pauseEnd) {
            Write-Log 'INFO' ("Pause nach manuellem Lauf bis " + $pauseEnd.ToString('yyyy-MM-dd HH:mm') + '. Ende.')
        } else {
            Write-Log 'INFO' ("Zyklus " + $script:Due.ToString('yyyy-MM-dd') + " entfiel wegen manuellem Lauf (Pause bis " + $pauseEnd.ToString('yyyy-MM-dd HH:mm') + "). Naechster Zyklus: Freitag " + $script:Due.AddDays(7).ToString('yyyy-MM-dd') + '. Ende.')
        }
        return 0
    }
    if ($st.DoneCycle -ge $script:DueKey) { Write-Log 'INFO' 'Kein offener Zyklus. Ende.'; return 0 }

    Initialize-Cycle $st
    $gate = Get-AttemptGate $st
    if ($gate -eq 'DayDone') { Write-Log 'INFO' 'Heute keine weiteren Versuche. Naechster Versuch morgen nach der Anmeldung. Ende.'; return 0 }
    if ($gate -eq 'Wait') { Write-Log 'INFO' 'Abstand zwischen Fehlversuchen noch nicht erreicht. Ende.'; return 0 }

    if ($st.FollowUp) { Invoke-FollowUp $st; return 0 }

    $today = Get-Today
    $userPresent = Test-UserSession
    # Erster Updatetag = Tag der ersten Abfrage. Danach: Installation mit Hinweis ohne neue Abfrage.
    $askDay = 0
    if ($st.FirstAskAt -gt 0) { $askDay = [int](ConvertFrom-Epoch $st.FirstAskAt).ToString('yyyyMMdd') }
    $interactive = ($askDay -eq 0 -or $askDay -eq $today)

    if (-not $st.Downloaded) {
        if (-not (Test-DueDay) -and -not $userPresent) { Write-Log 'INFO' 'Nachholen erst nach der Anmeldung (ohne Anmeldung kein VPN). Ende.'; return 0 }
        if (-not (Step-Download $st)) {
            if ($script:NoUpdates) { Complete-NoUpdates $st }
            return 0
        }
    }

    if (-not $st.Consent) {
        if (-not $interactive) {
            $st.Consent = $true; $st.AutoConsent = $true; Save-State $st
            Write-Log 'INFO' 'Folgetag nach dem ersten Updatetag: Installation mit Hinweis ohne neue Abfrage.'
        } elseif (-not $userPresent -and -not (Test-CitrixProcess)) {
            $st.Consent = $true; $st.AutoConsent = $true; Save-State $st
            Write-Log 'INFO' 'Keine Benutzersitzung und keine Citrix-Prozesse: Installation ohne Abfrage.'
        } elseif ($userPresent) {
            if ($st.FirstAskAt -eq 0) {
                Invoke-Ask $st 1
                if (-not $st.Consent -and $st.FirstAskAt -gt 0) { Set-Reminder ($ReminderHours * 60) }
            } elseif (-not $st.Round2Done -and (Get-Epoch) -ge ($st.FirstAskAt + [long]$ReminderHours * 3600)) {
                Invoke-Ask $st 2
            } else {
                Write-Log 'INFO' 'Warte auf Abfrage 2 bzw. den Folgetag.'
            }
        } else {
            Write-Log 'WARN' 'Citrix-Prozesse ohne Benutzersitzung. Keine Abfrage moeglich, warte.'
        }
    }
    if ($st.Consent) { Invoke-InstallPath $st }
    return 0
}

# ---------------- Einzelinstanz ----------------
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Global\PatchPilot_Run', [ref]$created)
if (-not $created) {
    Write-Host 'Update-Run laeuft bereits. Abbruch.'
    try { if (Test-Path -LiteralPath $LogDir) { Write-Log 'INFO' ("Update-Run (Modus $Mode, Quelle $Source): ein anderer Lauf ist noch aktiv, dieser Start endet. Exitcode " + (Get-CodeText 'Run' 5)) } } catch { Write-Host 'Log nicht schreibbar.' }
    exit 5
}
$code = 0
try { $code = [int](@(Invoke-Main)[-1]) }
catch {
    # Unerwarteter Abbruch: Grund und Zeile ins Log (und damit ins Fehlerlog)
    $where = ''
    try { $where = " (Zeile $($_.InvocationInfo.ScriptLineNumber))" } catch { $where = '' }
    Write-Host ("Unerwarteter Fehler: " + $_.Exception.Message)
    try { Write-Log 'ERROR' ("Unerwarteter Abbruch: " + $_.Exception.Message + $where) } catch { Write-Host 'Log nicht schreibbar.' }
    $code = 3
}
finally {
    try {
        $summary = $script:LastInfo
        if ($null -ne $script:Buffer -and $code -eq 0) {
            $prev = Read-State
            if ($summary -and $summary -eq [string]$prev.LastRunSummary) {
                $script:Buffer = $null
                Write-Log 'INFO' ("Erneuter Start nach $($script:RepeatMin) Min., nichts Neues: $summary Update-Run beendet, Exitcode " + (Get-CodeText 'Run' $code))
            } else {
                Stop-LogBuffer
                Write-Log 'INFO' ("Update-Run beendet, Exitcode " + (Get-CodeText 'Run' $code))
            }
        } else {
            Stop-LogBuffer
            Write-Log 'INFO' ("Update-Run beendet, Exitcode " + (Get-CodeText 'Run' $code))
        }
        if (Test-Path -LiteralPath $StateDir) {
            $fin = Read-State
            $fin.LastRunEnd = Get-Epoch; $fin.LastRunSummary = $summary
            Save-State $fin
        }
    } catch { Write-Host ('Endzeile/Zustand nicht schreibbar: ' + $_.Exception.Message) }
    $mutex.ReleaseMutex(); $mutex.Dispose()
}
exit $code
