# Claude-Ampel 🚦

A small window that always stays on top and shows a traffic light ("Ampel") for every running
[Claude Code](https://claude.com/claude-code) session. That way you can see at a glance which of
your parallel sessions is currently waiting for you.

| Colour | Meaning |
|---|---|
| 🟢 Green | Done, waiting for your next message |
| 🟡 Yellow | Working |
| 🔴 Red (blinking) | Needs your input (question, plan approval, permission) |
| 🔵 Blue | Currently running a shell command (Bash/PowerShell) |

- **Click** a light to bring that session's terminal to the front – including the right tab in Windows Terminal.
- **Hover** shows folder and status.
- **Drag** with the left mouse button to move the window (the position is saved).
- **Right-click** → *Quit Ampel*.
- When a terminal is closed, its light disappears automatically.
- When no session is running, the window is gone completely – it reappears with the next session.
- **Usage limits:** next to the lights you can see how much of the **5-hour limit** and the **weekly limit** is used
  and when it resets (the same values as `/usage`). Hover shows the remaining time, click refreshes immediately.
  From 70 % the number turns yellow, from 90 % red.

---

## Requirements

- **Windows 10 or 11** (the light uses WPF and Windows PowerShell, both included with Windows)
- **[Claude Code](https://claude.com/claude-code)**
- **[Node.js](https://nodejs.org)** – the hook that reports the status is a Node script.
  Check in a terminal with `node -v`. If the command isn't found: install Node.js (LTS).

## Installation

1. **Download:** click the green **Code → Download ZIP** button at the top of this page
   (or `git clone https://github.com/Ovitrinker/claude-ampel.git`).
2. **Extract** it to a place where the folder can stay, e.g. `C:\Tools\claude-ampel`.
   Don't leave it in the Downloads folder – the settings point to this path afterwards.
3. **Double-click `Install.cmd`.**
   If Windows shows "Windows protected your PC": *More info → Run anyway*.
4. **Restart any open Claude Code sessions.** Hooks are only loaded when a session starts.

That's it. The light appears at the bottom right of the screen and from now on starts automatically with Windows.

### What the installer does

- adds the hooks to `%USERPROFILE%\.claude\settings.json`
  (a backup `settings.json.bak-ampel-<date>` is created first; your other settings and hooks stay unchanged),
- creates a **Claude-Ampel** shortcut on the desktop and in startup,
- starts the light.

Options if you don't want the shortcuts (run in PowerShell inside the folder):

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -NoAutostart -NoDesktop
```

If you move the folder later, simply run `Install.cmd` again in the new location.

## Uninstalling

Double-click **`Uninstall.cmd`**. This removes the hooks and the shortcuts, quits the light and
deletes the stored states. After that you can delete the folder.

## How it works

```
Claude Code ──hook event──▶ hook.js ──writes──▶ %LOCALAPPDATA%\claude-ampel\sessions\<id>.json
                                                              │
                                           ampel.ps1 reads every 0.4 s ◀┘
```

| File | Purpose |
|---|---|
| `hook.js` | Called by Claude Code on every hook event; writes the session's status to a small JSON file. |
| `ampel.ps1` | The light window (WPF). Reads the status files and shows one light per session. |
| `focus.ps1` | On click, brings the matching terminal or Windows Terminal tab to the front. |
| `start-ampel.vbs` | Starts the light without a visible console window. |
| `setup-hooks.js` | Adds the hooks to `settings.json` or removes them. |
| `install.ps1` / `uninstall.ps1` | Installation and uninstallation (called by `Install.cmd` / `Uninstall.cmd`). |

Hook events used: `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `Stop`, `Notification`,
`PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`.
Subagents are ignored; only the main session counts.

The session states stay local on your machine. For the usage limits the light queries
`https://api.anthropic.com/api/oauth/usage` once a minute – using the login token Claude Code stores in
`%USERPROFILE%\.claude\.credentials.json` (read-only, like `/usage`). Without a Claude subscription login the display stays hidden.

## Troubleshooting

- **No light appears after starting a session:** was the session started *after* the installation?
  Is `node -v` available in the terminal?
- **The light stays invisible although a session is running:** check whether `%USERPROFILE%\.claude\settings.json` contains entries with `claude-ampel`.
- **Quitting the light while no session is running:** the window is invisible then and the right-click menu can't be reached –
  end the light's `powershell.exe` process in Task Manager, or start a session and quit via right-click.
- **Error log:** `%LOCALAPPDATA%\claude-ampel\error.log`
- **Clicking doesn't bring the terminal to the front:** works with Windows Terminal and the classic console.
  With other terminals (e.g. the VS Code terminal) it beeps instead.

## License

[MIT](LICENSE)
