#requires -Version 5.1
<#
=====================================================================
Update-Settings  (Patch Pilot 0.10.4, Windows-Update-Einstellungen protokollieren, nur lesen)
=====================================================================
ZWECK
  Schreibt die Windows-Update-Einstellungen, die zum Zeitpunkt des Laufs
  in der Registry stehen, als eine Zeile ins Log. So ist spaeter nachvollziehbar,
  ob der PC den WSUS genutzt hat und wer (Gruppenrichtlinie, Clientverwaltung o. a.)
  die Werte gerade gesetzt hat.

WANN WIRD GELOGGT
  - beim ersten Lauf des Tages (eine Zeile "Einstellungen: ...")
  - bei jedem Lauf, in dem sich ein Wert seit dem letzten Lauf geaendert hat
    (zusaetzlich eine Zeile "geaendert seit letztem Lauf: ...", als WARN)
  Sonst nichts, damit das Log kurz bleibt.
  WSUS nicht aktiv (keine Adresse oder UseWUServer ungleich 1): zusaetzlich WARN
  (steht dann auch im Fehlerlog).

GELESENE WERTE (Pfade laut Microsoft "Manage additional Windows Update settings")
  HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate
    WUServer, TargetGroup, TargetGroupEnabled, DoNotConnectToWindowsUpdateInternetLocations
  HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU
    UseWUServer, AUOptions, NoAutoUpdate, DetectionFrequencyEnabled, DetectionFrequency
  Windows-Update-Schnittstelle (Microsoft.Update.ServiceManager):
    Ist der WSUS als Standard-Dienst angemeldet?

ABLAUF
  1. Admin-Pruefung
  2. Werte lesen
  3. Mit dem letzten Stand vergleichen (State\settings_last.json)
  4. Ggf. loggen, neuen Stand speichern

DATENSCHUTZ
  Geloggt werden nur Einstellungswerte und die WSUS-Adresse (vom Nutzer
  ausdruecklich freigegeben). Keine Benutzer- oder Computernamen.

SICHERHEIT
  Nur lesen. Aendert keine Registry, keine Gruppenrichtlinie, nichts an WSUS.
  Fehler halten den Updatelauf nie auf (Exitcode 0 auch bei Lesefehlern, diese
  werden geloggt).

PARAMETER
  -Root  Programmordner (Standard C:\Fernwartung\PatchPilot)

AENDERUNGEN
  0.9.11 Standardordner fest wie bei allen Modulen. Die Vorversion nutzte $PSScriptRoot,
        das in Windows PowerShell 5.1 beim Start mit -File im param-Block leer
        ist (Fehler "leere Zeichenfolge", Exitcode 1).
        Fehler beim Vorbereiten der Pfade enden jetzt mit Exitcode 3 statt 1.

EXITCODES
  0 = normal beendet
  1 = nicht als Administrator gestartet
  3 = unerwarteter Fehler
=====================================================================
#>
[CmdletBinding()]
param(
    [string]$Root = 'C:\Fernwartung\PatchPilot'
)

$ErrorActionPreference = 'Stop'
try {
    if ([string]::IsNullOrWhiteSpace($Root)) { throw 'Programmordner (-Root) ist leer.' }
    $LogDir       = Join-Path $Root 'Logs'
    $StateDir     = Join-Path $Root 'State'
    $LogFile      = Join-Path $LogDir ('PatchPilot_{0}.log' -f (Get-Date -Format 'yyyy-MM'))
    $ErrFile      = Join-Path $LogDir ('PatchPilot_Fehler_{0}.log' -f (Get-Date -Format 'yyyy-MM'))
    $SettingsFile = Join-Path $StateDir 'settings_last.json'
} catch {
    Write-Host ('FEHLER beim Vorbereiten der Pfade: ' + $_.Exception.Message)
    exit 3
}
$LogTag       = 'Settings'
$KeyWU        = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$KeyAU        = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
$NotSet       = 'nicht gesetzt'

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

# Einen Registry-Wert lesen. Fehlt Schluessel oder Wert: "nicht gesetzt".
function Get-RegText([string]$Path, [string]$Name) {
    try {
        $v = (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop).$Name
        if ($null -eq $v -or "$v" -eq '') { return $NotSet }
        return [string]$v
    } catch {
        return $NotSet
    }
}

# Ist der WSUS bei der Windows-Update-Schnittstelle als Standard-Dienst angemeldet?
function Get-WsusDefaultService {
    try {
        $sm = New-Object -ComObject Microsoft.Update.ServiceManager
        foreach ($s in $sm.Services) {
            if ($s.IsManaged -and $s.IsDefaultAUService) { return 'ja' }
        }
        return 'nein'
    } catch {
        Write-Log 'WARN' ('Update-Dienste nicht lesbar: ' + $_.Exception.Message)
        return 'unbekannt'
    }
}

# Alle Rohwerte in fester Reihenfolge (fuer Vergleich und Log)
function Get-CurrentSettings {
    $v = [ordered]@{}
    $v['WUServer']               = Get-RegText $KeyWU 'WUServer'
    $v['UseWUServer']            = Get-RegText $KeyAU 'UseWUServer'
    $v['TargetGroup']            = Get-RegText $KeyWU 'TargetGroup'
    $v['TargetGroupEnabled']     = Get-RegText $KeyWU 'TargetGroupEnabled'
    $v['AUOptions']              = Get-RegText $KeyAU 'AUOptions'
    $v['NoAutoUpdate']           = Get-RegText $KeyAU 'NoAutoUpdate'
    $v['DetectionFrequencyEnabled'] = Get-RegText $KeyAU 'DetectionFrequencyEnabled'
    $v['DetectionFrequency']     = Get-RegText $KeyAU 'DetectionFrequency'
    $v['DoNotConnectToWU']       = Get-RegText $KeyWU 'DoNotConnectToWindowsUpdateInternetLocations'
    $v['WsusDefaultService']     = Get-WsusDefaultService
    return $v
}

# Ist der WSUS laut Registry die Quelle? (Adresse eingetragen UND UseWUServer = 1)
function Test-WsusActive($v) {
    return ($v['WUServer'] -ne $NotSet -and $v['UseWUServer'] -eq '1')
}

# Klartext laut Microsoft-Doku zu AUOptions
function Get-AutoUpdateText($v) {
    if ($v['NoAutoUpdate'] -eq '1') { return 'aus' }
    switch ($v['AUOptions']) {
        '1'     { return 'aus' }
        '2'     { return 'nur benachrichtigen' }
        '3'     { return 'laden, Installation auf Nachfrage' }
        '4'     { return 'laden und nach Zeitplan installieren' }
        '5'     { return 'lokaler Administrator entscheidet' }
        '7'     { return 'benachrichtigen fuer Installation und Neustart' }
        default { return 'Windows-Standard' }
    }
}

function Format-Settings($v) {
    $wsus = 'Nein'
    if (Test-WsusActive $v) { $wsus = 'Ja' }
    $group = $v['TargetGroup']
    if ($v['TargetGroupEnabled'] -ne '1') { $group = $group + ' (Zuordnung aus)' }
    $search = 'Windows-Standard'
    if ($v['DetectionFrequencyEnabled'] -eq '1' -and $v['DetectionFrequency'] -ne $NotSet) { $search = 'alle ' + $v['DetectionFrequency'] + ' Std.' }
    $block = 'nein'
    if ($v['DoNotConnectToWU'] -eq '1') { $block = 'ja' }
    return ('Einstellungen: WSUS-Adresse: {0} | WSUS aktiv: {1} (UseWUServer {2}) | Gruppe: {3} | Windows-Autoupdate: {4} (AUOptions {5}, NoAutoUpdate {6}) | Suche: {7} | Microsoft-Sperre: {8} | WSUS Standard-Dienst: {9}' -f
        $v['WUServer'], $wsus, $v['UseWUServer'], $group, (Get-AutoUpdateText $v), $v['AUOptions'], $v['NoAutoUpdate'], $search, $block, $v['WsusDefaultService'])
}

# Letzten Stand lesen. Unlesbar oder fehlend: $null (dann gilt der Lauf als erster des Tages).
function Read-LastSettings {
    if (-not (Test-Path -LiteralPath $SettingsFile)) { return $null }
    try {
        return (Get-Content -LiteralPath $SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        Write-Log 'WARN' 'Letzter Einstellungsstand unlesbar, wird neu angelegt.'
        return $null
    }
}

function Save-Settings([string]$Day, $v) {
    $obj = [pscustomobject]@{ Day = $Day; Values = [pscustomobject]$v }
    $tmp = $SettingsFile + '.tmp'
    [IO.File]::WriteAllText($tmp, ($obj | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $SettingsFile) { [IO.File]::Replace($tmp, $SettingsFile, [NullString]::Value) }
    else { [IO.File]::Move($tmp, $SettingsFile) }
}

function Invoke-Main {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'FEHLER: Bitte als Administrator starten.'
        return 1
    }
    foreach ($d in @($LogDir, $StateDir)) { if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }

    $today = Get-Date -Format 'yyyy-MM-dd'
    $now   = Get-CurrentSettings
    $last  = Read-LastSettings

    # Aenderungen seit dem letzten Lauf ermitteln
    $changes = @()
    if ($last -and $last.Values) {
        foreach ($k in $now.Keys) {
            $old = $NotSet
            $p = $last.Values.PSObject.Properties[$k]
            if ($null -ne $p -and $null -ne $p.Value) { $old = [string]$p.Value }
            if ($old -ne $now[$k]) { $changes += ('{0} {1} -> {2}' -f $k, $old, $now[$k]) }
        }
    }
    $firstToday = (-not $last -or [string]$last.Day -ne $today)

    if ($firstToday -or $changes.Count -gt 0) {
        if ($changes.Count -gt 0) { Write-Log 'WARN' ('Einstellungen geaendert seit letztem Lauf: ' + ($changes -join '; ')) }
        Write-Log 'INFO' (Format-Settings $now)
        if (-not (Test-WsusActive $now)) {
            Write-Log 'WARN' ('WSUS nicht aktiv (WSUS-Adresse: {0}, UseWUServer: {1}). Windows sucht dann direkt bei Microsoft.' -f $now['WUServer'], $now['UseWUServer'])
        }
    }

    try { Save-Settings $today $now }
    catch { Write-Log 'WARN' ('Einstellungsstand nicht speicherbar: ' + $_.Exception.Message) }
    return 0
}

$code = 0
try { $code = [int](@(Invoke-Main)[-1]) }
catch {
    Write-Host ('Unerwarteter Fehler: ' + $_.Exception.Message)
    try { Write-Log 'ERROR' ('Unerwarteter Fehler: ' + $_.Exception.Message) } catch { Write-Host 'Log nicht schreibbar.' }
    $code = 3
}
exit $code
