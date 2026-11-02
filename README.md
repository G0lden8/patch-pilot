# Patch Pilot

Ein schlankes Steuerprogramm (PowerShell) für Windows Update auf Windows-11-PCs
in Firmennetzen mit WSUS.

Patch Pilot installiert keine Updates "auf eigene Faust": Das macht weiterhin
Windows Update selbst (Windows Update Agent). Patch Pilot steuert nur **wann**
und **wie** das passiert: Zeitplan, Hinweisfenster für die Benutzer, Trennen von
Citrix-Sitzungen, Neustart und ein verständliches Logbuch.

Version: **0.10.4**

---

## Wofür ist Patch Pilot gedacht?

- **PCs mit Citrix-Nutzern:** Vor jeder Installation trennt Patch Pilot die
  Citrix-Sitzungen (offizieller Citrix-Befehl `SelfService.exe -disconnectapps`,
  der Benutzer wird **nicht** abgemeldet) und beendet die Citrix Workspace-App.
  Während der Installation steht ein Hinweis "Bitte warten – Citrix bitte nicht
  starten". So sollen Installationsfehler vermieden werden, die entstehen, wenn
  Citrix-Programme während der Updates laufen und Dateien belegen (z. B. bei
  .NET- oder Citrix-Updates). Folgt kein Neustart, wird die Workspace-App danach
  wieder gestartet.
- **Treiber und Firmware ohne WSUS-Freigabe:** Wichtige Treiber- und
  Firmware-Updates holt Patch Pilot direkt bei Microsoft (Windows Update). Sie
  müssen also nicht einzeln im WSUS freigegeben werden. Vorschau- und optionale
  Updates werden dabei nie genommen. Ein- und ausschaltbar, Standard: an.
- **Wenige, klare Hinweise:** Nie zwei Fenster gleichzeitig, kein Text doppelt,
  Fehlermeldungen nur, wenn der Benutzer selbst etwas tun kann (z. B. VPN
  verbinden) oder die IT Bescheid wissen sollte.
- **Kontrolle für die IT:** KB-Sperrliste, Notaus, Schalter für
  Funktionsupdates, Logdatei pro Monat in Klartext.

## Funktionen im Überblick

| Funktion | Kurz erklärt |
|---|---|
| Wöchentlicher Ablauf | Donnerstag Download vorladen, Freitag Abfrage, danach automatische Installation (siehe unten) |
| Desktop-Button | "Windows Updates jetzt starten" für den Benutzer, danach 5 Tage 12 Stunden Pause |
| Citrix-Trennung | Trennen statt Abmelden, Prüfung ob wirklich getrennt, sonst keine Installation |
| Treiber-Zusatz | Wichtige Treiber/Firmware direkt von Microsoft (`Treiber-Ein.bat` / `Treiber-Aus.bat`) |
| Direktbezug | Alle wichtigen Updates direkt bei Microsoft: automatisch nach 45 Tagen ohne WSUS-Kontakt (und mind. 5 Fehltagen) oder per `Direktbezug-Microsoft.bat` |
| KB-Sperrliste | `Config\Sperrliste.txt`: gesperrte Updates werden in Windows ausgeblendet und nie installiert, nur von Administratoren änderbar |
| Funktionsupdates | Laufen standardmäßig mit, abschaltbar mit `Funktionsupdates-Aus.bat` |
| Firmware & Akku | Firmware nur mit Netzteil oder ab 50 % Akku, sonst Netzteil-Abfrage bzw. nächster Lauf |
| Neustart | Nur wenn Windows ihn verlangt, mit 60 Sekunden Vorlauf |
| Offline-Installation | Bereits geladene Updates werden auch ohne erreichbaren WSUS installiert |
| Fehlerregel | Höchstens 3 Versuche am Freitag, danach stilles tägliches Nachholen; ein fehlerhaftes Update wird nie aufgegeben, aber nur noch 1× pro Woche versucht |
| Notaus | `Notaus.bat` stoppt alles sofort, `Notaus-Aufheben.bat` schaltet wieder ein |

## Zeitablauf

1. **Donnerstag (Standard 12:00):** Updates werden im Hintergrund geladen, der
   Benutzer merkt nichts.
2. **Freitag (Standard ab 06:00):** Abfrage "Jetzt installieren / Später".
   Bei "Später" kommt nach 4 Stunden eine zweite Abfrage.
3. **Ab Samstag:** Installation automatisch, mit kurzem Hinweis vorher.
4. **PC war länger aus?** Einmaliges Nachholen nach dem Start
   (verpasste Wochen werden nicht gestapelt).

Ist niemand angemeldet und läuft kein Citrix, wird ohne Abfrage installiert.
Die Uhrzeiten lassen sich bei der Installation ändern (`-PreloadTime`, `-FridayTime`).

## Voraussetzungen

- Windows 11, Windows PowerShell 5.1
- WSUS per Gruppenrichtlinie eingetragen. Patch Pilot liest die Adresse nur
  aus der Registry, im Code ist keine Adresse hinterlegt.
- Für Treiber-Zusatz und Direktbezug: Internetzugang zu Windows Update, und
  keine Gruppenrichtlinie, die Windows Update sperrt
  (`DoNotConnectToWindowsUpdateInternetLocations`, `DisableWindowsUpdateAccess`).
- Optional: Citrix Workspace-App (ohne Citrix entfällt die Trennung einfach).
- Installationsordner: `C:\Fernwartung\PatchPilot`

## Installation und Verteilung

Patch Pilot wird über die Windows-Aufgabenplanung betrieben (Aufgaben
`PatchPilot-*`), ein Dienst ist nicht nötig.

**Manuell (ein PC):**
Ordner auf den PC kopieren, `Installieren.bat` doppelklicken und die
Administrator-Abfrage bestätigen.

**Per Clientverwaltung (viele PCs):**
Im Ordner `Clientverwaltung/` liegen fertige Skripte für die Softwareverteilung
bzw. Clientverwaltung (Sprache PowerShell, 64 Bit, ausführen als SYSTEM). Sie
sind normale PowerShell-Skripte ohne Abhängigkeit von einem bestimmten Produkt
und laufen mit jedem Werkzeug, das ein Skript als SYSTEM ausführt
(z. B. Intune, Configuration Manager, PDQ oder ein RMM-Tool):

| Skript | Zweck |
|---|---|
| `Install-PatchPilot-Clientverwaltung_V0.10.4.ps1` | Installation, alle Dateien sind eingebettet und per SHA256 geprüft, kein Download |
| `Start-PatchPilot-Clientverwaltung_V0.10.4.ps1` | Updatelauf aus der Ferne starten (ohne Startabfrage) |
| `Set-PatchPilot-Funktionsupdates-Clientverwaltung_V0.10.4.ps1` | Funktionsupdates ein-/ausschalten |
| `Uninstall-PatchPilot-Clientverwaltung_V0.10.4.ps1` | Deinstallation |

Alternativ den Programmordner verteilen und `Install-PatchPilot.ps1` als
SYSTEM starten. Getestet wurde bisher mit einem RMM-Tool und manuell.

## Bedienung für Administratoren

Nach der Installation liegen im Programmordner diese Startdateien
(fordern Administratorrechte an):

- `Treiber-Ein.bat` / `Treiber-Aus.bat` – Treiber-Zusatz von Microsoft
- `Funktionsupdates-Ein.bat` / `Funktionsupdates-Aus.bat`
- `Direktbezug-Microsoft.bat` – jetzt alle wichtigen Updates direkt bei Microsoft holen
- `Notaus.bat` / `Notaus-Aufheben.bat`
- `Deinstall.bat`

**KB-Sperrliste** (`Config\Sperrliste.txt`), eine Zeile pro Eintrag:

```
# Kommentar
KB5034441
0b5c1a6e-1234-4c0d-9a3e-1f2e3d4c5b6a   # Update-ID, z. B. für Treiber ohne KB-Nummer
```

## Logging

- Eine Logdatei pro Monat: `Logs\PatchPilot_<Jahr-Monat>.log`
- Zusätzlich nur Warnungen/Fehler: `Logs\PatchPilot_Fehler_<Jahr-Monat>.log`
- Logs älter als 12 Monate werden automatisch gelöscht.
- Klartext statt Zahlencodes, z. B. `Exitcode 2 = Suche fehlgeschlagen`.
- Die Windows-Update-Einstellungen (WSUS aktiv, Gruppe, Autoupdate …) werden
  einmal täglich und bei jeder Änderung protokolliert.
- Hat Windows Updates ohne Patch Pilot installiert, steht das als Warnung im Log.
- Keine Benutzernamen, keine Rechnernamen.

## Deinstallation

`Deinstall.bat` im Programmordner (als Administrator) oder das
Deinstallationsskript aus dem Ordner `Clientverwaltung/`. Entfernt Aufgaben, Desktop-Verknüpfung und
Programmordner (fremde Dateien bleiben liegen und werden gemeldet). Von Patch
Pilot gesperrte, also ausgeblendete Updates werden wieder eingeblendet.

## Was Patch Pilot bewusst nicht tut

- Keine Änderungen an WSUS, Gruppenrichtlinien oder der Updatequelle
  (setzt z. B. `UseWUServer` nie selbst zurück).
- Kein Abmelden von Citrix, nur Trennen.
- Keine Endlos-Wiederholungen.
- Keine Übertragung von Daten an Dritte.

## Haftungsausschluss

Benutzung auf eigene Gefahr, ohne Gewähr. Patch Pilot installiert echte
Updates und startet PCs neu. Bitte zuerst auf Test-PCs ausprobieren, bevor es
breit verteilt wird.

## Lizenz

MIT-Lizenz, siehe [LICENSE](LICENSE). Freie Nutzung, Änderung und Weitergabe, solange der Lizenzhinweis erhalten bleibt.
