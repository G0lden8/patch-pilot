#requires -Version 5.1
<#
=====================================================================
Update-Power  (Patch Pilot 0.10.4, Strom-Pruefung vor Firmware-Updates, nur lesen)
=====================================================================
ZWECK
  Prueft vor der Installation, ob unter den bereits geladenen Updates ein
  Firmware-Update ist (z. B. BIOS/UEFI) und ob der PC gerade am Akku laeuft.
  Nur dann braucht es die Netzteil-Abfrage (Update-User -Action Power).
  Schreibt dazu eine Logzeile mit Geraetetyp, Akkustand und Netzteil.

ABLAUF
  1. Lokale Suche (Online=false, kein Netzwerk) nach geladenen, nicht
     installierten Updates; Firmware = Treiber mit Treiberklasse "Firmware"
     (Windows-Update-Schnittstelle IWindowsDriverUpdate.DriverClass)
  2. Stromstatus von Windows (SystemInformation.PowerStatus:
     PowerLineStatus, BatteryChargeStatus, BatteryLifePercent)
  3. Exitcode fuer Update-Run

REGEL (vom Nutzer festgelegt)
  Firmware nur, wenn Netzteil angeschlossen ODER Akku mindestens 50 %.
  Desktop-PC (kein Akku) oder am Netzteil: keine Abfrage.

SICHERHEIT / DATENSCHUTZ
  Nur lesen. Keine Installation, keine Aenderung. Keine Benutzer- oder
  Rechnernamen im Log.

PARAMETER
  -Root  Programmordner (Standard C:\Fernwartung\PatchPilot)

EXITCODES
  0  = keine Firmware geladen, oder Netzteil angeschlossen, oder kein Akku
  30 = Firmware geladen, Akkubetrieb, Akku mindestens 50 %
  31 = Firmware geladen, Akkubetrieb, Akku unter 50 %
  1  = nicht als Administrator gestartet
  2  = Pruefung nicht moeglich (Update-Run installiert dann normal; Windows
       und die Firmware pruefen den Akku zusaetzlich selbst)
=====================================================================
#>
[CmdletBinding()]
param(
    [string]$Root = 'C:\Fernwartung\PatchPilot'
)

$ErrorActionPreference = 'Stop'
$LogDir  = Join-Path $Root 'Logs'
$LogFile = Join-Path $LogDir ('PatchPilot_{0}.log' -f (Get-Date -Format 'yyyy-MM'))
$ErrFile = Join-Path $LogDir ('PatchPilot_Fehler_{0}.log' -f (Get-Date -Format 'yyyy-MM'))
$LogTag  = 'Power'
$MinPercent = 50

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

# Stromstatus laut Windows. Liefert Objekt mit HasBattery, OnAC, Percent.
function Get-PowerInfo {
    Add-Type -AssemblyName System.Windows.Forms
    $ps = [System.Windows.Forms.SystemInformation]::PowerStatus
    $noBattery = (($ps.BatteryChargeStatus -band [System.Windows.Forms.BatteryChargeStatus]::NoSystemBattery) -ne 0)
    $percent = -1
    if (-not $noBattery -and $ps.BatteryLifePercent -le 1) { $percent = [int][math]::Round($ps.BatteryLifePercent * 100) }
    return [pscustomobject]@{
        HasBattery = -not $noBattery
        OnAC       = ([string]$ps.PowerLineStatus -eq 'Online')
        Percent    = $percent
    }
}

function Get-DeviceType {
    try {
        switch ([int](Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).PCSystemType) {
            1 { return 'Desktop' } 2 { return 'Laptop' } 3 { return 'Workstation' } default { return 'unbekannt' }
        }
    } catch { return 'unbekannt' }
}

function Invoke-Main {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'FEHLER: Bitte als Administrator starten.'
        return 1
    }

    # 1. Firmware unter den geladenen Updates?
    $fw = @()
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $session.ClientApplicationID = 'PatchPilot'
        $searcher = $session.CreateUpdateSearcher()
        $searcher.ServerSelection = 0
        $searcher.Online = $false
        $found = $searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Driver'")
        foreach ($u in $found.Updates) {
            $cls = ''
            try { $cls = [string]$u.DriverClass } catch { $cls = '' }
            if ($cls -eq 'Firmware' -and $u.IsDownloaded) { $fw += [string]$u.Title }
        }
    } catch {
        Write-Log 'WARN' ('Firmware-Pruefung nicht moeglich: 0x{0:X8}. Installation laeuft normal weiter.' -f $_.Exception.HResult)
        return 2
    }

    # 2. Stromstatus
    try { $p = Get-PowerInfo }
    catch {
        Write-Log 'WARN' ('Stromstatus nicht lesbar: ' + $_.Exception.GetType().Name + '. Installation laeuft normal weiter.')
        return 2
    }
    $akku = 'kein Akku'
    if ($p.HasBattery) { $akku = "$($p.Percent) %"; if ($p.Percent -lt 0) { $akku = 'unbekannt' } }
    $netz = 'nein'; if ($p.OnAC) { $netz = 'ja' }
    Write-Log 'INFO' ("Strom: Geraet {0} | Akku {1} | Netzteil angeschlossen: {2} | geladene Firmware-Updates: {3}" -f (Get-DeviceType), $akku, $netz, $fw.Count)
    foreach ($t in $fw) { Write-Log 'INFO' ('Firmware: ' + $t) }

    # 3. Entscheidung
    if ($fw.Count -eq 0) { return 0 }
    if (-not $p.HasBattery -or $p.OnAC) { Write-Log 'INFO' 'Firmware: Netzteil angeschlossen oder kein Akku, keine Abfrage noetig.'; return 0 }
    if ($p.Percent -ge $MinPercent) { Write-Log 'WARN' "Firmware: Akkubetrieb, Akku $akku (mindestens $MinPercent %)."; return 30 }
    Write-Log 'WARN' "Firmware: Akkubetrieb, Akku $akku (unter $MinPercent %)."
    return 31
}

$code = 2
try { $code = [int](@(Invoke-Main)[-1]) }
catch {
    Write-Host ('Unerwarteter Fehler: ' + $_.Exception.Message)
    try { Write-Log 'WARN' ('Update-Power unerwarteter Fehler: ' + $_.Exception.Message) } catch { Write-Host 'Log nicht schreibbar.' }
    $code = 2
}
exit $code
