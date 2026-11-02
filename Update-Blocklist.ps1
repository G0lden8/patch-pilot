#requires -Version 5.1
<#
=====================================================================
Update-Blocklist  (Patch Pilot 0.10.4, Sperrliste, wird eingebunden)
=====================================================================
ZWECK
  Gemeinsame Funktionen fuer die Sperrliste. Wird von Update-Core,
  Update-Install, Update-Microsoft und Uninstall-PatchPilot per
  Punkt-Aufruf eingebunden (. Update-Blocklist.ps1), laeuft nie allein.
  Der Aufrufer muss eine Funktion Write-Log und die Variable $Root haben.

WIE GESPERRT WIRD (Windows-Bordmittel)
  Ein gesperrtes Update wird in Windows "ausgeblendet" (IUpdate.IsHidden),
  genau wie mit dem Microsoft-Werkzeug wushowhide oder mit
  PSWindowsUpdate (Hide-WindowsUpdate). Ausgeblendete Updates installiert
  dann weder Patch Pilot noch Windows selbst noch ein anderes Werkzeug.
  Patch Pilot merkt sich, was es selbst ausgeblendet hat (State\hidden.json),
  und blendet nur diese Updates wieder ein, wenn sie von der Liste
  entfernt werden. Von anderen ausgeblendete Updates bleiben unberuehrt.

SPERRLISTE  <Root>\Config\Sperrliste.txt
  Eine Zeile pro Eintrag, Kommentare mit #:
    KB-Nummer        z. B. KB5034441 (oder nur 5034441)
    Update-ID        z. B. 0b5c1a6e-1234-4c0d-9a3e-1f2e3d4c5b6a
                     (steht im Log bei jedem Update hinter "ID",
                     noetig fuer Treiber, die oft keine KB-Nummer haben)
  Aendern duerfen nur Administratoren und SYSTEM (Ordnerrechte).

FUNKTIONSUPDATES (ab 0.10.2)
  Schalter Config\Funktionsupdates-Aus (Funktionsupdates-Ein.bat / -Aus.bat).
  Ohne Datei: Funktionsupdates laufen mit (Standard). Mit Datei: Updates der
  Kategorie "Upgrades" werden auf allen Wegen uebersprungen, aber nicht
  ausgeblendet (wieder einschalten wirkt sofort beim naechsten Lauf).

SICHERHEIT / DATENSCHUTZ
  Liest nur die Sperrliste, schreibt nur State\hidden.json. Fehler halten
  den Lauf nie auf (dann ohne Sperrliste weiter, WARN im Log).
=====================================================================
#>

$script:BlockFile  = Join-Path $Root 'Config\Sperrliste.txt'
$script:HiddenFile = Join-Path $Root 'State\hidden.json'
$script:Blocklist  = $null
$script:FeatureOffFile = Join-Path $Root 'Config\Funktionsupdates-Aus'   # vorhanden = Funktionsupdates aus (Standard: an)
$script:UpgradesCat = '3689bdc8-b205-4af4-8d4a-a63924c5e9d5'            # Windows-Update-Kategorie "Upgrades" (Funktionsupdates)

# Ist das Update ein Funktionsupdate (neue Windows-Version)? Erkennung ueber die Kategorie "Upgrades".
function Test-FeatureUpdate($U) {
    try {
        foreach ($c in @($U.Categories)) { if (([string]$c.CategoryID).ToLowerInvariant() -eq $script:UpgradesCat) { return $true } }
    } catch { Write-Log 'WARN' 'Kategorie eines Updates nicht lesbar.' }
    return $false
}

# Funktionsupdates ausgeschaltet: diese Updates in den uebergebenen Sperr-IDs ergaenzen (nur ueberspringen, nicht ausblenden).
function Add-FeatureSkips($Updates, $Ids) {
    if (-not (Test-Path -LiteralPath $script:FeatureOffFile)) { return }
    foreach ($u in $Updates) {
        if (-not (Test-FeatureUpdate $u)) { continue }
        $id = ([string]$u.Identity.UpdateID).ToLowerInvariant()
        if ($Ids.ContainsKey($id)) { continue }
        $Ids[$id] = $true
        Write-Log 'INFO' ("Funktionsupdate uebersprungen (Schalter Funktionsupdates aus): {0}" -f $u.Title)
    }
}

# Liest die Sperrliste einmal pro Lauf. Liefert @{ KB = @{nummer=$true}; Id = @{guid=$true}; Count = n }
function Read-Blocklist {
    if ($null -ne $script:Blocklist) { return $script:Blocklist }
    $set = @{ KB = @{}; Id = @{}; Count = 0 }
    $script:Blocklist = $set
    if (-not (Test-Path -LiteralPath $script:BlockFile)) { return $set }
    try {
        $lines = @(Get-Content -LiteralPath $script:BlockFile -Encoding UTF8 -ErrorAction Stop)
    } catch {
        Write-Log 'WARN' ('Sperrliste nicht lesbar (' + $_.Exception.GetType().Name + '). Weiter ohne Sperrliste.')
        return $set
    }
    foreach ($raw in $lines) {
        $l = ([string]$raw -replace '#.*$', '').Trim()
        if (-not $l) { continue }
        if ($l -match '^(?:[Kk][Bb])?(\d{6,8})$') { $set.KB[$Matches[1]] = $true; $set.Count++; continue }
        $g = [guid]::Empty
        if ([guid]::TryParse($l, [ref]$g)) { $set.Id[$g.ToString()] = $true; $set.Count++; continue }
        $show = $l; if ($show.Length -gt 60) { $show = $show.Substring(0, 60) + '...' }
        Write-Log 'WARN' "Sperrliste: Eintrag nicht erkannt, ignoriert: $show"
    }
    if ($set.Count -gt 0) { Write-Log 'INFO' "Sperrliste: $($set.Count) Eintraege" }
    return $set
}

# Steht das Update (per KB-Nummer oder Update-ID) auf der Sperrliste?
function Test-Blocked($U) {
    $set = Read-Blocklist
    if ($set.Count -eq 0) { return $false }
    try { if ($set.Id.ContainsKey(([string]$U.Identity.UpdateID).ToLowerInvariant())) { return $true } } catch { Write-Log 'WARN' 'Sperrliste: Update-ID nicht lesbar.' }
    foreach ($kb in @($U.KBArticleIDs)) { if ($set.KB.ContainsKey([string]$kb)) { return $true } }
    return $false
}

function Read-HiddenList {
    if (-not (Test-Path -LiteralPath $script:HiddenFile)) { return @() }
    try { return @(Get-Content -LiteralPath $script:HiddenFile -Raw -Encoding UTF8 | ConvertFrom-Json | Where-Object { $_ -and $_.Id }) }
    catch { Write-Log 'WARN' 'Liste der ausgeblendeten Updates unlesbar, wird neu begonnen.'; return @() }
}

function Save-HiddenList($List) {
    $dir = Split-Path -Parent $script:HiddenFile
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $tmp = $script:HiddenFile + '.tmp'
    [IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject @($List) -Depth 3), (New-Object Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $script:HiddenFile) { [IO.File]::Replace($tmp, $script:HiddenFile, [NullString]::Value) }
    else { [IO.File]::Move($tmp, $script:HiddenFile) }
}

# Blendet gesperrte Updates aus einer Suchliste aus. Liefert die Update-IDs (klein geschrieben) der
# gesperrten Updates, damit der Aufrufer sie in diesem Lauf ueberspringt.
function Set-BlockedHidden($Updates) {
    $ids = @{}
    $set = Read-Blocklist
    if ($set.Count -eq 0) { return $ids }
    $list = [System.Collections.ArrayList]@(Read-HiddenList)
    $changed = $false
    foreach ($u in $Updates) {
        if (-not (Test-Blocked $u)) { continue }
        $id = ([string]$u.Identity.UpdateID).ToLowerInvariant()
        $ids[$id] = $true
        $kb = @($u.KBArticleIDs | ForEach-Object { 'KB' + $_ }) -join ','
        if ($u.IsHidden) { Write-Log 'INFO' ("Gesperrt (Sperrliste), bereits ausgeblendet: {0} | {1} | ID {2}" -f $u.Title, $kb, $id); continue }
        try {
            $u.IsHidden = $true
            Write-Log 'WARN' ("Gesperrt (Sperrliste), in Windows ausgeblendet: {0} | {1} | ID {2}" -f $u.Title, $kb, $id)
            if (-not @($list | Where-Object { $_.Id -eq $id }).Count) {
                [void]$list.Add([pscustomobject]@{ Id = $id; KB = $kb; Title = [string]$u.Title })
                $changed = $true
            }
        } catch {
            Write-Log 'WARN' ("Gesperrt, aber Ausblenden nicht moeglich (0x{0:X8}), wird in diesem Lauf uebersprungen: {1}" -f $_.Exception.HResult, $u.Title)
        }
    }
    if ($changed) { try { Save-HiddenList $list } catch { Write-Log 'WARN' ('Liste der ausgeblendeten Updates nicht speicherbar: ' + $_.Exception.Message) } }
    return $ids
}

# Eintraege, die Patch Pilot ausgeblendet hat und die nicht mehr auf der Sperrliste stehen.
function Get-UnblockPending {
    $out = @()
    foreach ($e in @(Read-HiddenList)) {
        $still = $false
        $set = Read-Blocklist
        if ($set.Id.ContainsKey([string]$e.Id)) { $still = $true }
        foreach ($k in @(([string]$e.KB) -split ',' | Where-Object { $_ })) { if ($set.KB.ContainsKey(($k -replace '^KB', ''))) { $still = $true } }
        if (-not $still) { $out += $e }
    }
    return $out
}

# Blendet von Patch Pilot ausgeblendete Updates wieder ein, wenn sie nicht mehr gesperrt sind
# (oder alle, mit -All, z. B. bei der Deinstallation). Sucht dafuer nur, wenn es etwas zu tun gibt.
# ServerSelection: 0 = Windows-Standard (WSUS), 2 = Windows Update.
function Restore-UnblockedUpdates($Session, [int]$ServerSelection, [bool]$Online, [switch]$All) {
    if ($All) { $pending = @(Read-HiddenList) } else { $pending = @(Get-UnblockPending) }
    if ($pending.Count -eq 0) { return }
    try {
        $s = $Session.CreateUpdateSearcher()
        $s.ServerSelection = $ServerSelection
        $s.Online = $Online
        $s.IncludePotentiallySupersededUpdates = $true   # laut Microsoft noetig, um ausgeblendete Updates sicher zu finden
        $found = $s.Search('IsInstalled=0 and IsHidden=1')
    } catch {
        Write-Log 'WARN' ("Wieder einblenden: Suche nicht moeglich (0x{0:X8}), naechster Lauf." -f $_.Exception.HResult)
        return
    }
    $list = [System.Collections.ArrayList]@(Read-HiddenList)
    $changed = $false
    foreach ($u in $found.Updates) {
        $id = ([string]$u.Identity.UpdateID).ToLowerInvariant()
        if (-not @($pending | Where-Object { $_.Id -eq $id }).Count) { continue }
        try {
            $u.IsHidden = $false
            Write-Log 'INFO' ("Nicht mehr gesperrt, in Windows wieder eingeblendet: {0} | ID {1}" -f $u.Title, $id)
            foreach ($e in @($list | Where-Object { $_.Id -eq $id })) { $list.Remove($e); $changed = $true }
        } catch {
            Write-Log 'WARN' ("Wieder einblenden nicht moeglich (0x{0:X8}): {1}" -f $_.Exception.HResult, $u.Title)
        }
    }
    if ($changed) { try { Save-HiddenList $list } catch { Write-Log 'WARN' ('Liste der ausgeblendeten Updates nicht speicherbar: ' + $_.Exception.Message) } }
}
