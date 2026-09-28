# Claude-Ampel 🚦

Ein kleines Fenster, das immer im Vordergrund bleibt und für jede laufende
[Claude Code](https://claude.com/claude-code)-Session eine Ampel zeigt. So siehst du auf einen Blick,
welche deiner parallel laufenden Sessions gerade auf dich wartet.

| Farbe | Bedeutung |
|---|---|
| 🟢 Grün | Fertig, wartet auf deine nächste Nachricht |
| 🟡 Gelb | Arbeitet |
| 🔴 Rot (blinkt) | Braucht deine Eingabe (Rückfrage, Plan-Freigabe, Berechtigung) |
| 🔵 Blau | Führt gerade einen Shell-Befehl aus (Bash/PowerShell) |

- **Klick** auf eine Ampel holt das Terminal dieser Session nach vorne – auch den richtigen Tab in Windows Terminal.
- **Mouseover** zeigt Ordner und Status.
- **Ziehen** mit der linken Maustaste verschiebt das Fenster (Position wird gespeichert).
- **Rechtsklick** → *Ampel beenden*.
- Wird ein Terminal geschlossen, verschwindet die zugehörige Ampel automatisch.

> *English:* A tiny always-on-top traffic light for every running Claude Code session on Windows.
> Green = done, yellow = working, red = needs your input, blue = running a shell command.
> Install: download, run `Installieren.cmd`, restart your Claude Code sessions.

---

## Voraussetzungen

- **Windows 10 oder 11** (die Ampel nutzt WPF und Windows-PowerShell, beides ist bei Windows dabei)
- **[Claude Code](https://claude.com/claude-code)**
- **[Node.js](https://nodejs.org)** – der Hook, der den Status meldet, ist ein Node-Skript.
  Prüfen im Terminal mit `node -v`. Falls der Befehl nicht gefunden wird: Node.js (LTS) installieren.

## Installation

1. **Herunterladen:** Oben auf dieser Seite auf den grünen Knopf **Code → Download ZIP** klicken
   (oder `git clone https://github.com/Ovitrinker/claude-ampel.git`).
2. **Entpacken** an einen Ort, wo der Ordner bleiben kann, z. B. `C:\Tools\claude-ampel`.
   Nicht im Download-Ordner lassen – die Einstellungen zeigen danach fest auf diesen Pfad.
3. **Doppelklick auf `Installieren.cmd`.**
   Falls Windows „Der Computer wurde durch Windows geschützt" anzeigt: *Weitere Informationen → Trotzdem ausführen*.
4. **Offene Claude-Code-Sessions neu starten.** Hooks werden nur beim Start einer Session geladen.

Das war's. Die Ampel erscheint unten rechts am Bildschirm und startet ab jetzt automatisch mit Windows.

### Was der Installer macht

- trägt die Hooks in `%USERPROFILE%\.claude\settings.json` ein
  (vorher wird ein Backup `settings.json.bak-ampel-<Datum>` angelegt; deine anderen Einstellungen und Hooks bleiben unverändert),
- legt eine Verknüpfung **Claude-Ampel** auf dem Desktop und im Autostart an,
- startet die Ampel.

Optionen, falls du keine Verknüpfungen willst (in PowerShell im Ordner ausführen):

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -NoAutostart -NoDesktop
```

Wenn du den Ordner später verschiebst, einfach `Installieren.cmd` am neuen Ort nochmals ausführen.

## Deinstallation

Doppelklick auf **`Deinstallieren.cmd`**. Das entfernt die Hooks, die Verknüpfungen, beendet die Ampel
und löscht die gespeicherten Stati. Danach kannst du den Ordner löschen.

## Wie es funktioniert

```
Claude Code ──Hook-Event──▶ hook.js ──schreibt──▶ %LOCALAPPDATA%\claude-ampel\sessions\<id>.json
                                                              │
                                              ampel.ps1 liest alle 0,4 s ◀┘
```

| Datei | Aufgabe |
|---|---|
| `hook.js` | Wird von Claude Code bei jedem Hook-Event aufgerufen und schreibt den Status der Session in eine kleine JSON-Datei. |
| `ampel.ps1` | Das Ampel-Fenster (WPF). Liest die Status-Dateien und zeigt eine Ampel pro Session. |
| `focus.ps1` | Holt beim Klick das passende Terminal bzw. den Windows-Terminal-Tab nach vorne. |
| `start-ampel.vbs` | Startet die Ampel ohne sichtbares Konsolenfenster. |
| `setup-hooks.js` | Trägt die Hooks in `settings.json` ein bzw. entfernt sie. |
| `install.ps1` / `uninstall.ps1` | Installation und Deinstallation (`Installieren.cmd` / `Deinstallieren.cmd` rufen sie auf). |

Benutzte Hook-Events: `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `Stop`, `Notification`,
`PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`.
Subagenten werden ignoriert, es zählt nur die Haupt-Session.

Es werden keine Daten verschickt – alles bleibt lokal auf deinem Rechner.

## Probleme?

- **Keine Ampel erscheint nach dem Start einer Session:** Wurde die Session *nach* der Installation gestartet?
  Ist `node -v` im Terminal verfügbar?
- **Ampel bleibt auf „-":** Prüfen, ob in `%USERPROFILE%\.claude\settings.json` Einträge mit `claude-ampel` stehen.
- **Fehlerprotokoll:** `%LOCALAPPDATA%\claude-ampel\error.log`
- **Klick holt das Terminal nicht nach vorne:** Funktioniert mit Windows Terminal und der klassischen Konsole.
  Bei anderen Terminals (z. B. im Terminal von VS Code) piept es stattdessen.

## Lizenz

[MIT](LICENSE)
