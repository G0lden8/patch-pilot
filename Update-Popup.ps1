#requires -Version 5.1
<#
=====================================================================
Update-Popup  (Patch Pilot 0.10.4, Fensterregel und Windows-Hinweise fuer Patch Pilot)
=====================================================================
ZWECK
  Gemeinsame Funktionen fuer Update-Notify und Update-User. Wird dort per
  Punkt-Aufruf eingebunden (. Update-Popup.ps1), laeuft nie allein.
  Sorgt dafuer, dass immer nur EIN Fenster von Patch Pilot offen ist.

STUFEN
  1 = niedrig    (Status, Fertig)           -> Windows-Hinweis unten rechts
  2 = mittel     (Fehlerhinweise)
  3 = hoch       (Abfrage, Desktop-Symbol, IT-Hinweis): danach passiert
                 nichts ohne den Benutzer, daher darf es warten
  4 = Countdown  (Hinweis vor der Citrix-Trennung, Netzteil-Abfrage):
                 danach passiert automatisch etwas
                 (Vorbild: Configuration Manager / PSAppDeployToolkit,
                 Countdown-Fenster vor automatischen Aktionen gehen vor)

REGELN
  - Kein Fenster offen: sofort anzeigen.
  - Sonst warten, bis das offene Fenster bestaetigt oder abgelaufen ist.
  - Nach 2 Minuten Warten: Ist das neue Fenster wichtiger als das offene,
    wird das offene geschlossen und das neue erscheint.
  - Countdown (Stufe 4) ersetzt ein offenes, weniger wichtiges Fenster
    SOFORT, weil sonst Warnzeit verloren geht. Countdown wartet nur auf
    einen anderen Countdown.
  - Ein ersetztes Fenster stellt sich wieder hinten an (Update-Notify),
    es geht also nichts verloren.
  - Stufe 1 und 2 verfallen nach der Verfallszeit (Standard 30 Minuten):
    dann erscheint nichts mehr. Stufe 3 und 4 verfallen nie.
  - Wer warten musste, erscheint mit 3 Sekunden Abstand.
  - Windows-Hinweise (Stufe 1) brauchen keine Sperre: Windows reiht sie
    selbst ein. Gleiche Kennung (Tag) ersetzt den alten Hinweis, so
    ersetzt "Fertig" ein noch sichtbares "Updates werden geladen".
    Der Citrix-Hinweis entfernt den Status-Hinweis (Clear-PopupToast).

TECHNIK
  Benannte Windows-Objekte nur in der eigenen Sitzung (Local\), Standard-
  muster aus .NET (Mutex = Sperre, EventWaitHandle = Signal):
    Local\PatchPilot_Popup          Sperre: wer sie hat, zeigt sein Fenster
    Local\PatchPilot_Popup_Stufe<N> zeigt an, welche Stufe offen ist
    Local\PatchPilot_Popup_Close    Bitte an das offene Fenster: schliessen
  Windows-Hinweis: Absendername "Patch Pilot" ueber den Registry-Schluessel
  HKCU\Software\Classes\AppUserModelId\PatchPilot (DisplayName), so wie im
  bewaehrten Vorlage-Skript "Important Toast Notifications". Der
  Schluessel liegt im Benutzerprofil, Benutzerrechte genuegen.

SICHERHEIT / DATENSCHUTZ
  Keine Dateien, keine Netzwerkzugriffe, keine Benutzernamen. Schreibt nur
  den genannten Schluessel im eigenen Benutzerprofil.
=====================================================================
#>

$script:PopupMutex     = $null
$script:PopupOwned     = $false
$script:PopupLevelEvt  = $null
$script:PopupCloseEvt  = $null
$script:PopupWaitedSec = 0
$script:PopupLevel     = 0
$PopupAppId   = 'PatchPilot'
$PopupAppName = 'Patch Pilot'

# Hoechste gerade offene Stufe (0 = keine bekannt)
function Get-OpenPopupLevel {
    foreach ($n in 4, 3, 2, 1) {
        $h = $null
        if ([Threading.EventWaitHandle]::TryOpenExisting("Local\PatchPilot_Popup_Stufe$n", [ref]$h)) {
            $h.Dispose()
            return $n
        }
    }
    return 0
}

# Wartet, bis dieses Fenster an der Reihe ist. $true = jetzt anzeigen, $false = verfallen.
function Enter-Popup([int]$Level, [int]$ExpireSeconds = 1800) {
    $script:PopupLevel = $Level
    $script:PopupMutex    = New-Object Threading.Mutex($false, 'Local\PatchPilot_Popup')
    $script:PopupCloseEvt = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::AutoReset, 'Local\PatchPilot_Popup_Close')
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $asked = $false
    while (-not $script:PopupOwned) {
        try { $script:PopupOwned = $script:PopupMutex.WaitOne(1000) }
        catch [Threading.AbandonedMutexException] {
            # Vorheriges Fenster wurde hart beendet: Sperre gehoert jetzt uns
            $script:PopupOwned = $true
        }
        if ($script:PopupOwned) { break }
        $sec = $sw.Elapsed.TotalSeconds
        $askAfter = 120; if ($Level -ge 4) { $askAfter = 0 }   # Countdown ersetzt sofort
        # Countdown fragt bei jedem Durchlauf erneut (falls ein anderes Fenster dazwischenrutscht)
        if ((-not $asked -or $Level -ge 4) -and $sec -ge $askAfter -and $Level -gt (Get-OpenPopupLevel)) {
            [void]$script:PopupCloseEvt.Set()
            if (-not $asked) { Write-Host "Offenes Fenster ist weniger wichtig: es wird ersetzt (nach $askAfter s Warten)." }
            $asked = $true
        }
        if ($Level -lt 3 -and $sec -ge $ExpireSeconds) {
            Write-Host 'Meldung verfallen (zu lange auf ein offenes Fenster gewartet). Kein Fenster.'
            Exit-Popup
            return $false
        }
    }
    $script:PopupWaitedSec = [int]$sw.Elapsed.TotalSeconds
    [void]$script:PopupCloseEvt.Reset()   # alte Schliess-Bitte verwerfen, sie galt dem vorigen Fenster
    $script:PopupLevelEvt = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, "Local\PatchPilot_Popup_Stufe$Level")
    if ($script:PopupWaitedSec -ge 1 -and $Level -lt 4) {   # Countdown ohne Abstand: Warnzeit zaehlt
        Write-Host "Auf ein offenes Fenster gewartet: $($script:PopupWaitedSec) s."
        Start-Sleep -Seconds 3
    }
    return $true
}

# Gibt die Sperre frei. Mehrfacher Aufruf ist unschaedlich.
function Exit-Popup {
    if ($script:PopupLevelEvt) { $script:PopupLevelEvt.Dispose(); $script:PopupLevelEvt = $null }
    if ($script:PopupMutex) {
        if ($script:PopupOwned) { $script:PopupMutex.ReleaseMutex(); $script:PopupOwned = $false }
        $script:PopupMutex.Dispose(); $script:PopupMutex = $null
    }
    if ($script:PopupCloseEvt) { $script:PopupCloseEvt.Dispose(); $script:PopupCloseEvt = $null }
}

# Haengt an ein Fenster eine Pruefung (jede Sekunde): Bittet ein wichtigeres Fenster
# um Platz, schliesst sich dieses Fenster mit dem Ergebnis "Cancel".
# Countdown (Stufe 4) wird nie ersetzt, daher dort keine Pruefung.
function Add-PopupCloseWatch($Form) {
    if ($script:PopupLevel -ge 4) { return }
    $watch = New-Object System.Windows.Forms.Timer
    $watch.Interval = 1000
    $evt = $script:PopupCloseEvt
    $watch.Add_Tick({
        if ($evt -and $evt.WaitOne(0)) {
            $watch.Stop()
            Write-Host 'Fenster durch ein wichtigeres ersetzt.'
            $Form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
            $Form.Close()
        }
    }.GetNewClosure())
    $watch.Start()
}

# Windows-Hinweis unten rechts. Erste Zeile = Ueberschrift, Rest = Text.
# Gleiches -Tag ersetzt einen noch sichtbaren Hinweis. Liefert $false bei Fehler.
function Show-PopupToast([string]$Text, [string]$Tag = 'Status') {
    try {
        $key = 'HKCU:\Software\Classes\AppUserModelId\' + $PopupAppId
        if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }
        Set-ItemProperty -LiteralPath $key -Name 'DisplayName' -Value $PopupAppName

        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

        $lines = @($Text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $head = [Security.SecurityElement]::Escape($lines[0])
        $body = ''
        if ($lines.Count -gt 1) { $body = '<text>' + [Security.SecurityElement]::Escape(($lines[1..($lines.Count - 1)] -join ' ')) + '</text>' }
        $xmlText = '<toast><visual><binding template="ToastGeneric"><text>' + $head + '</text>' + $body + '</binding></visual></toast>'

        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml($xmlText)
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        $toast.Tag = $Tag
        $toast.Group = $PopupAppId
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($PopupAppId).Show($toast)
        Write-Host 'Windows-Hinweis angezeigt.'
        return $true
    } catch {
        Write-Host ('Windows-Hinweis nicht moeglich: ' + $_.Exception.Message)
        return $false
    }
}

# Entfernt einen noch sichtbaren Windows-Hinweis von Patch Pilot (gleiche Kennung = Tag) aus dem
# Infobereich, z. B. den Status-Hinweis, sobald der Citrix-Hinweis erscheint (nur eine Meldung zur Zeit).
# Offizielle Windows-Schnittstelle ToastNotificationHistory.Remove(tag, group, applicationId).
# Fehler sind harmlos (Hinweis bleibt dann einfach stehen) und halten nichts auf.
function Clear-PopupToast([string]$Tag = 'Status') {
    try {
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [Windows.UI.Notifications.ToastNotificationManager]::History.Remove($Tag, $PopupAppId, $PopupAppId)
        Write-Host 'Windows-Hinweis entfernt.'
    } catch {
        Write-Host ('Windows-Hinweis nicht entfernbar: ' + $_.Exception.Message)
    }
}

# Wie Show-PopupToast, bleibt aber stehen (kein Verschwinden nach Sekunden), bis der Benutzer es
# wegklickt. Fuer einen laufenden Vorgang (z. B. "Wird heruntergeladen..."). Gleiches -Tag ersetzt
# einen noch sichtbaren Hinweis (auch eine fruehere Show-PopupToast-Meldung). Eigene Funktion,
# damit Show-PopupToast (bereits getestet) unveraendert bleibt. Liefert $false bei Fehler.
function Show-PopupToastReminder([string]$Text, [string]$Tag = 'Status') {
    try {
        $key = 'HKCU:\Software\Classes\AppUserModelId\' + $PopupAppId
        if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }
        Set-ItemProperty -LiteralPath $key -Name 'DisplayName' -Value $PopupAppName

        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

        $lines = @($Text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $head = [Security.SecurityElement]::Escape($lines[0])
        $body = ''
        if ($lines.Count -gt 1) { $body = '<text>' + [Security.SecurityElement]::Escape(($lines[1..($lines.Count - 1)] -join ' ')) + '</text>' }
        # Ab 0.10.3: Erinnerungs-Hinweise brauchen laut Microsoft mindestens einen Knopf, sonst behandelt
        # Windows sie wie normale Hinweise und blendet sie nach wenigen Sekunden aus (so war es in 0.10.2).
        # activationType="system" + "dismiss" ist der Standard-Schliessen-Knopf (kein eigener Code noetig).
        $xmlText = '<toast scenario="reminder"><visual><binding template="ToastGeneric"><text>' + $head + '</text>' + $body + '</binding></visual>' +
                   '<actions><action content="Schlie' + [char]0x00DF + 'en" arguments="dismiss" activationType="system"/></actions></toast>'

        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml($xmlText)
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        $toast.Tag = $Tag
        $toast.Group = $PopupAppId
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($PopupAppId).Show($toast)
        Write-Host 'Windows-Hinweis (bleibt stehen) angezeigt.'
        return $true
    } catch {
        Write-Host ('Windows-Hinweis nicht moeglich: ' + $_.Exception.Message)
        return $false
    }
}
