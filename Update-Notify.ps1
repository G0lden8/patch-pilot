#requires -Version 5.1
<#
=====================================================================
Update-Notify  (Patch Pilot 0.10.4, Hinweise fuer den Benutzer)
=====================================================================
ZWECK
  Laeuft im Konto des angemeldeten Benutzers und zeigt EINEN kurzen
  Hinweis. Regel: so wenig wie moeglich, nie zwei kurz nacheinander,
  nichts doppelt. Ein Fenster (nur "OK") gibt es nur, wenn der Benutzer
  etwas tun kann oder die IT Bescheid wissen muss. Alles andere ist ein
  Windows-Hinweis unten rechts. Technische Details stehen nur im Log.

ARTEN (-Kind)
  Fenster:
  Net            Freitag: Suche/Download nicht moeglich, meist kein VPN.
                 Rat: VPN verbinden (falls noetig Neustart).
  Final          IT-Hinweis: seit 2 Wochen an mindestens 5 Tagen keine
                 Updates geladen. Bitte der IT Bescheid sagen.
  Done           Desktop-Button: abgeschlossen (ab 0.10.4 Fenster mit OK statt
                 Windows-Hinweis; bleibt stehen, bis OK gedrueckt wird,
                 hoechstens -TimeoutMinutes).
  Partial        Desktop-Button: abgeschlossen, einzelne Updates werden
                 beim naechsten Lauf erneut versucht (ab 0.10.4 Fenster mit OK).
  NoOffer        IT-Hinweis: WSUS erreichbar, bietet aber seit 45 Tagen
                 keine Updates an. Bitte der IT Bescheid sagen.
  Windows-Hinweis (alle mit derselben Kennung "Status": der neue ersetzt
  den alten, es steht also immer nur einer da):
  Running        Desktop-Button: Updates werden geladen und installiert.
                 Bleibt stehen, bis er ersetzt wird.
  ManualNet      Desktop-Button: nicht geladen, VPN pruefen und erneut starten.
  ManualGeneric  Desktop-Button: nicht moeglich, spaeter erneut starten.

FENSTERREGEL (Update-Popup.ps1, liegt im selben Ordner)
  Stufe 1 niedrig: Windows-Hinweise (klappt das nicht: normales Fenster)
  Stufe 2 mittel:  Net, Done, Partial
  Stufe 3 hoch:    Final, NoOffer (IT-Hinweise)
  Nur ein Fenster zur Zeit. Wichtigeres ersetzt nach 2 Minuten Warten,
  Countdown sofort. Wird dieses Fenster ersetzt, stellt es sich wieder
  hinten an (hoechstens 3 Mal). Stufe 1/2 verfallen nach 30 Minuten Warten.

VORAUSSETZUNGEN
  Windows 11, PowerShell 5.1, normaler Benutzer (kein Admin noetig).
  Wird vom SYSTEM-Skript ueber feste Aufgaben PatchPilot-User-* gestartet.

SICHERHEIT
  Zeigt nur Text an. Keine Dateien, keine Befehle, keine Eingaben.

PARAMETER
  -Kind            Net | Final | NoOffer | Running | Done | Partial | ManualNet | ManualGeneric
  -TimeoutMinutes  Fenster schliesst sich selbst nach dieser Zeit (10)

DATENSCHUTZ
  Keine Logdatei, keine Benutzernamen.

EXITCODES
  0 = Hinweis angezeigt (oder durch Zeitablauf/wichtigeres Fenster geschlossen)
  2 = Fenster konnte nicht angezeigt werden
  5 = verfallen (zu lange auf ein offenes Fenster gewartet), nichts angezeigt
=====================================================================
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Net','Final','NoOffer','Running','Done','Partial','ManualNet','ManualGeneric')][string]$Kind,
    [ValidateRange(1, 240)][int]$TimeoutMinutes = 10
)

$ErrorActionPreference = 'Stop'

$Button = "Desktop-Symbol `"Windows Updates jetzt starten`""

switch ($Kind) {
    'Net' {
        $Text = "Die Windows-Updates konnten nicht geladen werden.`n`n" +
                "Das VPN ist möglicherweise nicht verbunden. Bitte verbinden Sie das VPN " +
                "(falls nötig: PC neu starten und am VPN anmelden).`n`n" +
                "Wir versuchen es heute später erneut, sonst morgen nach der Anmeldung. " +
                "Sie können die Updates auch selbst am Feierabend starten: $Button."
    }
    'Final' {
        $Text = "Bitte sagen Sie der IT Bescheid.`n`n" +
                "Es konnten seit 2 Wochen an mindestens 5 Tagen keine Windows-Updates geladen werden."
    }
    'NoOffer' {
        $Text = "Bitte sagen Sie der IT Bescheid.`n`n" +
                "Der Update-Server bietet diesem PC seit 45 Tagen keine Windows-Updates an."
    }
    'Running' {
        $Text = "Updates werden geladen und installiert`n" +
                "Sie können weiterarbeiten. Vor der Installation erhalten Sie einen kurzen Hinweis."
    }
    'Done' {
        $Text = "Die Windows-Updates sind abgeschlossen.`n`n" +
                "Sie können normal weiterarbeiten und Citrix wieder verwenden."
    }
    'Partial' {
        $Text = "Die Windows-Updates sind abgeschlossen.`n`n" +
                "Einzelne Updates werden beim nächsten Lauf erneut versucht. Sie müssen nichts tun. " +
                "Sie können normal weiterarbeiten und Citrix wieder verwenden."
    }
    'ManualNet' {
        $Text = "Die Updates konnten nicht geladen werden`n" +
                "Bitte verbinden Sie das VPN und starten Sie erneut über das $Button."
    }
    'ManualGeneric' {
        $Text = "Die Updates konnten gerade nicht ausgeführt werden`n" +
                "Bitte versuchen Sie es später erneut über das $Button."
    }
}

# Stufe festlegen (siehe FENSTERREGEL)
$Level = 1
if ($Kind -eq 'Net' -or $Kind -eq 'Done' -or $Kind -eq 'Partial') { $Level = 2 }   # Done/Partial ab 0.10.4 als Fenster
if ($Kind -eq 'Final' -or $Kind -eq 'NoOffer') { $Level = 3 }

$popupLib = 'C:\Fernwartung\PatchPilot\Update-Popup.ps1'
if ($PSScriptRoot) { $popupLib = Join-Path $PSScriptRoot 'Update-Popup.ps1' }
try { . $popupLib } catch { Write-Host ('Fensterregel nicht ladbar: ' + $_.Exception.Message); exit 2 }

# Stufe 1: Windows-Hinweis, keine Sperre noetig. Gleiche Kennung "Status" ersetzt den vorigen Hinweis.
# Running bleibt stehen (laufender Vorgang), bis ein anderer Hinweis ihn ersetzt.
# Running ist nur ein Status: klappt kein Windows-Hinweis, kein Ersatzfenster (weniger ist mehr).
if ($Kind -eq 'Running') {
    if (Show-PopupToastReminder $Text 'Status') { exit 0 }
    if (Show-PopupToast $Text 'Status') { exit 0 }
    exit 2
}
if ($Level -eq 1 -and (Show-PopupToast $Text 'Status')) { exit 0 }

# Zeigt das Hinweisfenster einmal. Liefert das Ergebnis (OK, Cancel = durch wichtigeres Fenster ersetzt).
function Show-NotifyWindow {
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
    $form.ClientSize = New-Object System.Drawing.Size(460, 250)
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point(20, 20)
    $label.Size = New-Object System.Drawing.Size(420, 170)
    $form.Controls.Add($label)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'OK'
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $ok.Location = New-Object System.Drawing.Point(165, 200)
    $ok.Size = New-Object System.Drawing.Size(130, 36)
    $form.Controls.Add($ok)
    $form.AcceptButton = $ok

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = [Math]::Max(1000, $TimeoutMinutes * 60 * 1000)
    $timer.Add_Tick({ $timer.Stop(); $form.DialogResult = [System.Windows.Forms.DialogResult]::OK; $form.Close() })
    $timer.Start()
    $form.Add_Shown({ $form.WindowState = 'Normal'; $form.TopMost = $true; $form.Activate(); $form.BringToFront() })
    $focus = New-Object System.Windows.Forms.Timer
    $focus.Interval = 400
    $focus.Add_Tick({ $focus.Stop(); $form.TopMost = $true; $form.Activate(); $form.BringToFront() })
    $focus.Start()
    Add-PopupCloseWatch $form
    $result = $form.ShowDialog()
    $timer.Dispose(); $focus.Dispose(); $form.Dispose()
    return $result
}

# Fenster: ein noch sichtbarer Status-Hinweis ("Updates werden geladen ...") wird entfernt,
# damit nie zwei Meldungen gleichzeitig dastehen.
if ($Level -ge 2) { Clear-PopupToast 'Status' }

try {
    for ($round = 1; $round -le 3; $round++) {
        if (-not (Enter-Popup $Level)) { exit 5 }
        $r = Show-NotifyWindow
        Exit-Popup
        if ($r -ne [System.Windows.Forms.DialogResult]::Cancel) { exit 0 }
        Write-Host "Ersetzt durch ein wichtigeres Fenster, stellt sich wieder an (Runde $round von 3)."
        Start-Sleep -Seconds 2   # dem wichtigeren Fenster den Vortritt lassen
    }
    exit 0
} catch {
    Write-Host ("Hinweisfenster nicht anzeigbar: " + $_.Exception.Message)
    Exit-Popup
    exit 2
}
