#requires -Version 5.1
<#
=====================================================================
Update-User  (Patch Pilot 0.10.4, Benutzersitzung: Dialoge + Citrix-Trennung)
=====================================================================
ZWECK
  Laeuft im Konto des angemeldeten Benutzers (NICHT als SYSTEM), weil nur
  dort Fenster angezeigt und die Citrix-Verbindung getrennt werden kann.
  Das SYSTEM-Skript startet dieses Skript per Aufgabenplanung und liest
  das Ergebnis aus dem Exitcode (LastTaskResult). Es werden keine Dateien
  zwischen den Konten ausgetauscht.

AKTIONEN (-Action)
  Ask         Ein Fenster mit "Jetzt installieren" / "Spaeter".
              -Round 1 = erste Abfrage, -Round 2 = Erinnerung nach 4 Stunden.
              Alle Abfragefenster bieten "Nach erfolgreichen Updates PC ausschalten"
              an (dann Exitcode 4 statt 0).
  Manual      Desktop-Button: Abfrage, danach startet dieses Skript per schtasks
              die SYSTEM-Aufgabe PatchPilot-Manual (oder PatchPilot-Manual-Shutdown).
  Notice      Hinweis direkt vor der Installation ohne Abfrage (Citrix wird
              getrennt), schliesst nach -NoticeSeconds selbst.
  Power       Netzteil-Abfrage vor Firmware-Updates (nur im Akkubetrieb, von
              Update-Run nach Update-Power gestartet): 120 s, Knoepfe
              "Ja, Moment" / "Nein, ohne Netzteil" / "Spaeter". Nach "Ja, Moment"
              Wartefenster mit "Jetzt weiter"; es schliesst sich, sobald das
              Netzteil erkannt wird, spaetestens nach 5 Minuten.
  Disconnect  Citrix trennen mit SelfService.exe -disconnectapps (offizieller
              Citrix-Befehl, CTX335905) und pruefen, dass die Citrix-Sitzungen
              beendet sind. Ab 0.10.4 danach die Citrix Workspace-App mit
              SelfService.exe -terminate beenden (Citrix-Befehl "Beenden"), damit
              man sich waehrend der Installation nicht mit einem Klick neu verbindet.
  Guard       Ab 0.10.4: kleines Fenster "Bitte warten - Citrix bitte nicht starten",
              immer im Vordergrund, nicht schliessbar. Steht waehrend der Installation;
              Update-Run beendet es danach (Aufgabe stoppen). Spaetestens nach
              -GuardMinutes schliesst es sich selbst. Keine Citrix-Aktion.
  Workspace   Ab 0.10.4: Citrix Workspace-App wieder starten (SelfService.exe), wenn
              Patch Pilot sie beendet hat und KEIN Neustart folgt. Laeuft sie schon:
              nichts tun.

FENSTERREGEL (Update-Popup.ps1, liegt im selben Ordner)
  Ask und Manual = Stufe 3 (hoch). Notice und Power = Stufe 4 (Countdown:
  danach passiert automatisch etwas), sie ersetzen ein offenes Fenster sofort.
  Nur ein Fenster zur Zeit; wartet ein Fenster, wird seine Wartezeit von der
  Anzeigedauer der Abfrage abgezogen (Update-Run wartet nicht ewig).
  Disconnect und Workspace zeigen kein Fenster und warten nie. Guard nimmt nicht an
  der Fensterregel teil (es steht nur waehrend der Installation, dann zeigt
  Patch Pilot kein anderes Fenster).

ABLAUF Disconnect
  1. Citrix-Sitzung aktiv? (Sitzungsprozesse wfica32, CDViewer,
     Citrix.DesktopViewer.App in der eigenen Sitzung). Wenn nein: Exitcode 10.
     SelfService.exe allein (Store-Programm) zaehlt nicht als Sitzung.
  2. SelfService.exe an festen Standardpfaden suchen (keine Registry):
     zuerst Program Files (x86) (32 Bit), dann Program Files (64 Bit,
     Citrix stellt ab Version 2603 auf 64 Bit um). Citrix-Signatur pruefen.
  3. Befehl ausfuehren und jede Sekunde pruefen, ob die Sitzungsprozesse
     verschwunden sind (Erkennung ueber wfica32 wie bei Patch My PC und
     PatchPilot). Sobald sie weg sind: fertig. Hoechstens 60 s, danach
     Exitcode 12.
  4. Ab 0.10.4: Laeuft die Workspace-App (SelfService.exe / Receiver.exe), wird sie
     mit SelfService.exe -terminate beendet (erst NACH der erfolgreichen Trennung,
     nie bei Exitcode 12). Das ist keine Sperre: der Benutzer kann sie jederzeit
     wieder starten. Auch ohne Citrix-Verbindung (Exitcode 10) wird eine offene
     Workspace-App beendet. Ob sie beendet ist, prueft Update-Run (SYSTEM).

VORAUSSETZUNGEN
  Windows 11, PowerShell 5.1, normaler Benutzer (kein Admin noetig).

SICHERHEIT
  Meldet NIEMALS ab und beendet keine Prozesse hart. Es werden ausschliesslich
  die Citrix-Befehle -disconnectapps und -terminate (und zum Wiederstarten
  SelfService.exe ohne Zusatz) ausgefuehrt, nur mit gueltiger Citrix-Signatur.

PARAMETER
  -Action          Ask | Notice | Disconnect | Manual | Power | Guard | Workspace
  -Round           1 oder 2 (nur Ask), Standard 1
  -TimeoutMinutes  Ask: Fenster schliesst nach dieser Zeit (Standard 240)
  -NoticeSeconds   Notice: Anzeigedauer (Standard 30)
  -GuardMinutes    Guard: Fenster schliesst sich spaetestens nach dieser Zeit (Standard 250)

DATENSCHUTZ
  Keine Logdatei, keine Benutzernamen. Nur Konsolenausgabe und Exitcode;
  protokolliert wird im SYSTEM-Teil.

EXITCODES
  0  = Ask: Zustimmung / Notice: angezeigt (volle Zeit) / Disconnect: getrennt und geprueft
  1000 + N = Notice: nach N Sekunden per OK oder Taste vorzeitig geschlossen (ab 0.10.3)
     / Manual: SYSTEM-Aufgabe gestartet
  4  = Ask: Zustimmung UND "PC nach den Updates ausschalten" gewaehlt
  1  = Ask: "Spaeter" gewaehlt / Manual: abgebrochen
  2  = Fehler (z. B. Fenster nicht anzeigbar)
  3  = Ask: keine Antwort (Zeit abgelaufen)
  10 = Disconnect: keine aktive Citrix-Verbindung, nichts zu tun
  11 = Disconnect: Befehl fehlgeschlagen oder Zeitueberschreitung
  12 = Disconnect: Befehl lief, aber Citrix-Prozesse sind noch aktiv
  13 = Disconnect: SelfService.exe nicht gefunden oder Signatur ungueltig
  5  = verfallen (zu lange auf ein offenes Fenster gewartet)
  Guard: 0 = Fenster nach -GuardMinutes selbst geschlossen (normal: Update-Run beendet es vorher)
  Workspace: 0 = gestartet, 10 = lief schon, 11 = Start fehlgeschlagen,
         13 = SelfService.exe nicht gefunden oder Signatur ungueltig
  Power: 0 = "Ja, Moment" (danach Netzteil erkannt, "Jetzt weiter" oder
         5 Minuten um), 1 = "Nein, ohne Netzteil", 6 = "Spaeter",
         3 = keine Antwort in 120 s, 2 = Fehler
=====================================================================
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Ask','Notice','Disconnect','Manual','Power','Guard','Workspace')][string]$Action,
    [ValidateSet(1,2)][int]$Round = 1,
    [int]$TimeoutMinutes = 240,
    [int]$NoticeSeconds = 30,
    [ValidateRange(5, 600)][int]$GuardMinutes = 250
)

$ErrorActionPreference = 'Stop'
# Sitzungsprozesse (eine Citrix-Verbindung ist offen). SelfService.exe allein ist keine Verbindung.
$CitrixProcs = @('wfica32.exe','CDViewer.exe','Citrix.DesktopViewer.App.exe')
# Citrix Workspace-App (Fenster mit den Verbindungen, Symbol neben der Uhr), ab 0.10.4
$WorkspaceProcs = @('SelfService.exe','Receiver.exe')
$SelfServicePaths = @(
    'C:\Program Files (x86)\Citrix\ICA Client\SelfServicePlugin\SelfService.exe',
    'C:\Program Files\Citrix\ICA Client\SelfServicePlugin\SelfService.exe'
)

function Show-Dialog([string]$Text, [bool]$AskButtons, [int]$Seconds, [string]$YesText = 'Jetzt installieren', [string]$NoText = 'Später', [bool]$OfferShutdown = $false) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Patch Pilot'
    $form.StartPosition = 'CenterScreen'
    $form.TopMost = $true
    $form.FormBorderStyle = 'FixedDialog'
    $form.ControlBox = $false
    $form.MinimizeBox = $false
    $form.MaximizeBox = $false
    $form.ShowInTaskbar = $true
    $dy = 0
    if ($OfferShutdown) { $dy = 36 }
    $form.ClientSize = New-Object System.Drawing.Size(460, (231 + $dy))
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point(20, 20)
    $label.Size = New-Object System.Drawing.Size(420, 150)
    $form.Controls.Add($label)

    $script:ShutdownChecked = $false
    $chk = $null
    if ($OfferShutdown) {
        $chk = New-Object System.Windows.Forms.CheckBox
        $chk.Text = 'Nach erfolgreichen Updates PC ausschalten'
        $chk.Location = New-Object System.Drawing.Point(20, 175)
        $chk.Size = New-Object System.Drawing.Size(420, 28)
        $form.Controls.Add($chk)
    }

    if ($AskButtons) {
        $yes = New-Object System.Windows.Forms.Button
        $yes.Text = $YesText
        $yes.DialogResult = [System.Windows.Forms.DialogResult]::Yes
        $yes.Location = New-Object System.Drawing.Point(80, (175 + $dy))
        $yes.Size = New-Object System.Drawing.Size(150, 36)
        $form.Controls.Add($yes)
        $no = New-Object System.Windows.Forms.Button
        $no.Text = $NoText
        $no.DialogResult = [System.Windows.Forms.DialogResult]::No
        $no.Location = New-Object System.Drawing.Point(250, (175 + $dy))
        $no.Size = New-Object System.Drawing.Size(130, 36)
        $form.Controls.Add($no)
        $form.AcceptButton = $yes
    } else {
        $ok = New-Object System.Windows.Forms.Button
        $ok.Text = 'OK'
        $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $ok.Location = New-Object System.Drawing.Point(165, (175 + $dy))
        $ok.Size = New-Object System.Drawing.Size(130, 36)
        $form.Controls.Add($ok)
        $form.AcceptButton = $ok
    }

    # Zeitablauf: Fenster schliesst selbst (Ergebnis Abort)
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = [Math]::Max(1000, $Seconds * 1000)
    $timer.Add_Tick({ $timer.Stop(); $form.DialogResult = [System.Windows.Forms.DialogResult]::Abort; $form.Close() })
    $timer.Start()
        $form.Add_Shown({ $form.WindowState = 'Normal'; $form.TopMost = $true; $form.Activate(); $form.BringToFront() })
    $focus = New-Object System.Windows.Forms.Timer
    $focus.Interval = 400
    $focus.Add_Tick({ $focus.Stop(); $form.TopMost = $true; $form.Activate(); $form.BringToFront() })
    $focus.Start()
    if ($script:PopupOwned) { Add-PopupCloseWatch $form }
    $dlgSw = [Diagnostics.Stopwatch]::StartNew()
    $result = $form.ShowDialog()
    $script:DialogSeconds = [int][math]::Floor($dlgSw.Elapsed.TotalSeconds)   # Standzeit (fuer den Notice-Exitcode)
    if ($chk) { $script:ShutdownChecked = $chk.Checked }
    $timer.Dispose(); $form.Dispose()
    return $result
}

function Get-CitrixActive {
    $sid = [Diagnostics.Process]::GetCurrentProcess().SessionId
    return @(Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.SessionId -eq $sid -and ($CitrixProcs -contains ($_.ProcessName + '.exe')) })
}

function Invoke-Ask {
    $yesText = 'Jetzt installieren'; $noText = 'Später'
    if ($Round -eq 1) {
        $text = "Es sind Windows-Updates zur Installation bereit.`n`n" +
                "Dafür wird Ihre Citrix-Verbindung getrennt (nicht abgemeldet). Ihre Programme in Citrix laufen weiter. " +
                "Danach startet der Computer eventuell neu.`n`n" +
                "Sie können die Updates jederzeit selbst über das Desktop-Symbol `"Windows Updates jetzt starten`" ausführen.`n`n" +
                "Jetzt installieren?"
    } else {
        $text = "Erinnerung: Die Windows-Updates sind noch nicht installiert.`n`n" +
                "Ihre Citrix-Verbindung wird dafür getrennt (nicht abgemeldet). Ihre Programme in Citrix laufen weiter. " +
                "Ohne Zustimmung werden die Updates morgen nach der Anmeldung automatisch installiert.`n`n" +
                "Sie können die Updates jederzeit selbst über das Desktop-Symbol `"Windows Updates jetzt starten`" ausführen.`n`n" +
                "Jetzt installieren?"
    }
    # Wartezeit auf ein anderes Fenster von der Anzeigedauer abziehen (mindestens 60 s)
    $sec = [Math]::Max(60, $TimeoutMinutes * 60 - $script:PopupWaitedSec)
    $r = Show-Dialog $text $true $sec $yesText $noText $true
    switch ($r.ToString()) {
        'Yes'   {
            if ($script:ShutdownChecked) { Write-Host 'Antwort: Jetzt, danach PC ausschalten'; return 4 }
            Write-Host 'Antwort: Jetzt'; return 0
        }
        'No'    { Write-Host 'Antwort: Später'; return 1 }
        'Abort' { Write-Host 'Keine Antwort (Zeit abgelaufen)'; return 3 }
        default { Write-Host "Unerwartetes Ergebnis: $r"; return 2 }
    }
}

function Invoke-Manual {
    Add-Type -AssemblyName System.Windows.Forms
    $text = "Updates jetzt installieren?`n`n" +
            "Zuerst werden die Updates geladen, " +
            "danach wird Ihre Citrix-Verbindung getrennt (nicht abgemeldet); Ihre Programme in Citrix laufen weiter. " +
            "Der Computer startet eventuell neu.`n`nTipp: Am besten starten Sie dies nach der Arbeit."
    $r = Show-Dialog $text $true 1800 'Jetzt starten' 'Abbrechen' $true
    if ($r.ToString() -ne 'Yes') { Write-Host 'Abgebrochen'; return 1 }
    $task = 'PatchPilot-Manual'
    if ($script:ShutdownChecked) { $task = 'PatchPilot-Manual-Shutdown' }
    $p = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\schtasks.exe') -ArgumentList @('/Run', '/TN', $task) -Wait -PassThru -NoNewWindow
    $rc = $p.ExitCode; $p.Dispose()
    if ($rc -eq 0) {
        # Keine eigene Erfolgsmeldung: die Bestaetigung "Gestartet" kommt von Update-Notify (nichts doppelt anzeigen).
        return 0
    }
    [void][System.Windows.Forms.MessageBox]::Show("Der Start war nicht möglich (Code $rc).`nBitte melden Sie sich beim IT-Support.", 'Patch Pilot', 'OK', 'Warning')
    return 2
}

function Invoke-Notice {
    $text = "Die Windows-Updates werden jetzt installiert.`n`n" +
            "Ihre Citrix-Verbindung wird getrennt (nicht abgemeldet) und die Citrix Workspace-App geschlossen. " +
            "Ihre Programme in Citrix laufen weiter. Danach startet der Computer eventuell neu."
    # Nur eine Meldung zur Zeit: der Status-Hinweis des manuellen Laufs wird durch dieses Fenster ersetzt.
    if (Get-Command -Name Clear-PopupToast -CommandType Function -ErrorAction SilentlyContinue) { Clear-PopupToast 'Status' }
    $res = Show-Dialog $text $false $NoticeSeconds
    # Ab 0.10.3: Schliessgrund und Standzeit im Exitcode (keine Logdatei in dieser Sitzung, Datenschutz):
    # 0 = volle Zeit angezeigt (Zeitablauf), 1000 + N = nach N Sekunden per OK/Taste geschlossen.
    if ($res -eq [System.Windows.Forms.DialogResult]::Abort) { Write-Host 'Hinweis angezeigt (volle Zeit)'; return 0 }
    Write-Host ("Hinweis nach $($script:DialogSeconds) Sekunden geschlossen")
    return (1000 + [math]::Min([int]$script:DialogSeconds, 998))
}

function Get-WorkspaceRunning {
    $sid = [Diagnostics.Process]::GetCurrentProcess().SessionId
    return @(Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.SessionId -eq $sid -and ($WorkspaceProcs -contains ($_.ProcessName + '.exe')) })
}

# SelfService.exe an den festen Standardpfaden, nur mit gueltiger Citrix-Signatur. Sonst $null.
function Find-SelfService {
    foreach ($cand in $SelfServicePaths) {
        if (-not (Test-Path -LiteralPath $cand -PathType Leaf)) { continue }
        $sig = Get-AuthenticodeSignature -LiteralPath $cand
        if ($sig.Status -eq 'Valid' -and $sig.SignerCertificate -and $sig.SignerCertificate.Subject -match '\bCitrix\b') {
            return $cand
        }
        Write-Host ("Signatur ungültig, übersprungen: " + $cand)
    }
    return $null
}

# Ab 0.10.4: Workspace-App mit dem Citrix-Befehl -terminate beenden (wie "Beenden" im Menue
# neben der Uhr). Nur aufrufen, wenn KEINE Citrix-Verbindung mehr offen ist. Keine Sperre:
# der Benutzer kann die App jederzeit wieder starten. Wartet hoechstens 30 Sekunden.
function Close-Workspace([string]$Exe) {
    if ((Get-WorkspaceRunning).Count -eq 0) { Write-Host 'Workspace-App läuft nicht.'; return }
    Write-Host ('Workspace-App wird beendet: ' + $Exe + ' -terminate')
    try {
        $p = Start-Process -FilePath $Exe -ArgumentList '-terminate' -PassThru
        $null = $p.Handle
    } catch {
        Write-Host ("Beenden der Workspace-App fehlgeschlagen: " + $_.Exception.Message)
        return
    }
    for ($i = 1; $i -le 30; $i++) {
        Start-Sleep -Seconds 1
        if ((Get-WorkspaceRunning).Count -eq 0) { Write-Host "Workspace-App beendet (nach $i s)."; return }
    }
    $left = (Get-WorkspaceRunning | ForEach-Object { $_.ProcessName } | Sort-Object -Unique) -join ', '
    Write-Host "Workspace-App noch aktiv: $left"
}

function Invoke-Disconnect {
    $active = ((Get-CitrixActive).Count -gt 0)
    $wsOpen = ((Get-WorkspaceRunning).Count -gt 0)
    if (-not $active -and -not $wsOpen) {
        Write-Host 'Keine aktive Citrix-Sitzung. Nichts zu tun.'
        return 10
    }
    $exe = Find-SelfService
    if (-not $exe) {
        Write-Host 'SelfService.exe an keinem Standardpfad gefunden (oder Signatur ungültig).'
        if (-not $active) { return 10 }   # keine Verbindung offen: Trennung nicht noetig
        return 13
    }
    if (-not $active) {
        Write-Host 'Keine aktive Citrix-Sitzung.'
        Close-Workspace $exe
        return 10
    }

    Write-Host ('Citrix wird getrennt: ' + $exe + ' -disconnectapps')
    try {
        $p = Start-Process -FilePath $exe -ArgumentList '-disconnectapps' -PassThru
        $null = $p.Handle
    } catch {
        Write-Host ("Citrix-Befehl fehlgeschlagen: " + $_.Exception.Message)
        return 11
    }

    $cmdDone = $false
    for ($i = 1; $i -le 60; $i++) {
        Start-Sleep -Seconds 1
        if (-not $cmdDone -and $p.HasExited) {
            Write-Host ('Citrix-Befehl beendet, Exitcode ' + $p.ExitCode)
            $cmdDone = $true
        }
        if ((Get-CitrixActive).Count -eq 0) {
            Write-Host ("Citrix getrennt und geprüft (nach $i s).")
            # Erst nach der erfolgreichen Trennung: Workspace-App schliessen (keine offene Verbindung mehr)
            Close-Workspace $exe
            return 0
        }
    }
    $left = (Get-CitrixActive | ForEach-Object { $_.ProcessName } | Sort-Object -Unique) -join ', '
    Write-Host "Noch aktive Citrix-Sitzungsprozesse: $left"
    return 12
}

# Ab 0.10.4: Workspace-App wieder starten (nur von Update-Run, wenn kein Neustart folgt).
function Invoke-Workspace {
    if ((Get-WorkspaceRunning).Count -gt 0) { Write-Host 'Workspace-App läuft bereits.'; return 10 }
    $exe = Find-SelfService
    if (-not $exe) { Write-Host 'SelfService.exe an keinem Standardpfad gefunden (oder Signatur ungültig).'; return 13 }
    try {
        $p = Start-Process -FilePath $exe -PassThru
        $p.Dispose()
        Write-Host 'Workspace-App gestartet.'
        return 0
    } catch {
        Write-Host ("Start der Workspace-App fehlgeschlagen: " + $_.Exception.Message)
        return 11
    }
}

# Ab 0.10.4: Hinweis waehrend der Installation. Immer im Vordergrund, nicht schliessbar
# (kein X, Alt+F4 wird ignoriert), stiehlt keinen Tastaturfokus. Update-Run beendet es
# nach der Installation, spaetestens nach -GuardMinutes schliesst es sich selbst.
function Invoke-Guard {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Patch Pilot'
    $form.TopMost = $true
    $form.FormBorderStyle = 'FixedDialog'
    $form.ControlBox = $false
    $form.MinimizeBox = $false
    $form.MaximizeBox = $false
    $form.ShowInTaskbar = $true
    $form.ClientSize = New-Object System.Drawing.Size(460, 170)
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    # Oben in der Mitte des Hauptbildschirms (verdeckt keine Fenstermitte)
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $form.StartPosition = 'Manual'
    $form.Location = New-Object System.Drawing.Point(([int]($wa.Left + ($wa.Width - $form.Width) / 2)), ($wa.Top + 40))

    $head = New-Object System.Windows.Forms.Label
    $head.Text = "Bitte warten: Citrix bitte nicht starten"
    $head.Font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
    $head.Location = New-Object System.Drawing.Point(20, 18)
    $head.Size = New-Object System.Drawing.Size(420, 30)
    $form.Controls.Add($head)

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Windows-Updates werden gerade installiert. Eine neue Citrix-Verbindung wird bis zum Ende automatisch wieder getrennt.`n`n" +
                  "Dieses Fenster schließt sich von selbst."
    $label.Location = New-Object System.Drawing.Point(20, 58)
    $label.Size = New-Object System.Drawing.Size(420, 100)
    $form.Controls.Add($label)

    $script:GuardEnd = $false
    $form.Add_FormClosing({ param($s, $e) if (-not $script:GuardEnd -and $e.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) { $e.Cancel = $true } })
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $tick = New-Object System.Windows.Forms.Timer
    $tick.Interval = 30000
    $tick.Add_Tick({
        if ($sw.Elapsed.TotalMinutes -ge $GuardMinutes) { $tick.Stop(); $script:GuardEnd = $true; $form.Close(); return }
        # Wieder ganz nach vorn (andere Fenster koennen ebenfalls "immer im Vordergrund" sein), ohne Fokus zu nehmen
        $form.TopMost = $false; $form.TopMost = $true
    })
    $tick.Start()
    $form.Add_Shown({ $form.TopMost = $true; $form.BringToFront() })
    [void]$form.ShowDialog()
    $tick.Dispose(); $form.Dispose()
    Write-Host 'Hinweis waehrend der Installation selbst geschlossen (Zeit abgelaufen).'
    return 0
}

# Einfaches Fenster mit bis zu drei Knoepfen. Liefert den Text des gedrueckten Knopfs
# oder 'Zeit' bei Zeitablauf.
# -StopWhen: Pruefung (Skriptblock) jede Sekunde; liefert sie $true, schliesst das Fenster mit 'Bedingung'.
function Show-ButtonDialog([string]$Text, [string[]]$Buttons, [int]$Seconds, [scriptblock]$StopWhen = $null) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Patch Pilot'
    $form.StartPosition = 'CenterScreen'
    $form.TopMost = $true
    $form.FormBorderStyle = 'FixedDialog'
    $form.ControlBox = $false
    $form.MinimizeBox = $false
    $form.MaximizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size(520, 250)
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point(20, 20)
    $label.Size = New-Object System.Drawing.Size(480, 165)
    $form.Controls.Add($label)
    $form.Tag = 'Zeit'   # gewaehlter Knopf (Ereignis-Bloecke schreiben ihn hierhin)
    $w = 150; $gap = 15
    $x = [int]((520 - ($Buttons.Count * $w + ($Buttons.Count - 1) * $gap)) / 2)
    foreach ($b in $Buttons) {
        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = $b
        $btn.Location = New-Object System.Drawing.Point($x, 195)
        $btn.Size = New-Object System.Drawing.Size($w, 36)
        $btn.Add_Click({ $f = $this.FindForm(); $f.Tag = $this.Text; $f.Close() })
        $form.Controls.Add($btn)
        $x += $w + $gap
    }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $tick = New-Object System.Windows.Forms.Timer
    $tick.Interval = 1000
    $tick.Add_Tick({
        if ($sw.Elapsed.TotalSeconds -ge $Seconds) { $tick.Stop(); $form.Tag = 'Zeit'; $form.Close(); return }
        if ($StopWhen -and (& $StopWhen)) { $tick.Stop(); $form.Tag = 'Bedingung'; $form.Close() }
    })
    $tick.Start()
    $form.Add_Shown({ $form.WindowState = 'Normal'; $form.TopMost = $true; $form.Activate(); $form.BringToFront() })
    [void]$form.ShowDialog()
    $choice = [string]$form.Tag
    $tick.Dispose(); $form.Dispose()
    return $choice
}

function Test-OnAC {
    Add-Type -AssemblyName System.Windows.Forms
    return ([string][System.Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus -eq 'Online')
}

function Invoke-Power {
    $text = "Gleich wird ein Firmware-Update installiert (Software im Geraet, z. B. BIOS).`n`n" +
            "Ihr Computer laeuft gerade ueber den Akku. Bitte schliessen Sie das Netzteil an. " +
            "Wird ein Firmware-Update unterbrochen, kann das Geraet unbrauchbar werden.`n`n" +
            "Ohne Antwort wird die Firmware in 2 Minuten auf spaeter verschoben, die anderen Updates werden installiert."
    $c = Show-ButtonDialog $text @('Ja, Moment', 'Nein, ohne Netzteil', 'Später') 120
    switch ($c) {
        'Nein, ohne Netzteil' { Write-Host 'Antwort: ohne Netzteil'; return 1 }
        'Später'              { Write-Host 'Antwort: Spaeter'; return 6 }
        'Ja, Moment'          { }
        default               { Write-Host "Keine Antwort ($c)"; return 3 }
    }
    $wait = "Bitte schliessen Sie jetzt das Netzteil an.`n`n" +
            "Es geht automatisch weiter, sobald das Netzteil erkannt wird, spaetestens in 5 Minuten."
    $c2 = Show-ButtonDialog $wait @('Jetzt weiter') 300 { Test-OnAC }
    Write-Host "Warten beendet: $c2"
    return 0
}

$popupLib = 'C:\Fernwartung\PatchPilot\Update-Popup.ps1'
if ($PSScriptRoot) { $popupLib = Join-Path $PSScriptRoot 'Update-Popup.ps1' }

$code = 2
try {
    if (@('Disconnect', 'Guard', 'Workspace') -notcontains $Action) {
        . $popupLib
        $level = 3; $expire = 1800
        if ($Action -eq 'Notice' -or $Action -eq 'Power') { $level = 4 }
        if (-not (Enter-Popup $level $expire)) { exit 5 }
    }
    switch ($Action) {
        'Ask'        { $code = Invoke-Ask }
        'Notice'     { $code = Invoke-Notice }
        'Disconnect' { $code = Invoke-Disconnect }
        'Manual'     { $code = Invoke-Manual }
        'Power'      { $code = Invoke-Power }
        'Guard'      { $code = Invoke-Guard }
        'Workspace'  { $code = Invoke-Workspace }
    }
} catch {
    Write-Host ("Unerwarteter Fehler: " + $_.Exception.Message)
    $code = 2
} finally {
    if (Get-Command -Name Exit-Popup -CommandType Function -ErrorAction SilentlyContinue) { Exit-Popup }
}
exit $code
