// Claude-Ampel Hook: schreibt den Status einer Claude-Code-Session in eine Datei,
// die ampel.ps1 anzeigt. Darf nie etwas ausgeben und nie fehlschlagen.
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const DIR = path.join(process.env.LOCALAPPDATA || os.tmpdir(), 'claude-ampel', 'sessions');
const SHELL_TOOLS = new Set(['Bash', 'PowerShell']);
const ASK_TOOLS = new Set(['AskUserQuestion', 'ExitPlanMode']);

function stateFor(e, prev) {
  switch (e.hook_event_name) {
    case 'SessionStart':
      // Auto-Compact passiert mitten in der Arbeit: Status dann nicht umwerfen
      return e.source === 'compact' && prev ? prev.state : 'green';
    case 'Stop':
      return 'green';
    case 'UserPromptSubmit':
    case 'PostToolUse':
    case 'PostToolUseFailure':
      return 'yellow';
    case 'PreToolUse':
      if (SHELL_TOOLS.has(e.tool_name)) return 'blue';
      if (ASK_TOOLS.has(e.tool_name)) return 'red';
      return 'yellow';
    case 'PermissionRequest':
      return 'red';
    case 'Notification': {
      const t = e.notification_type || '';
      if (t === 'permission_prompt' || t === 'elicitation_dialog') return 'red';
      if (!t && /permission/i.test(e.message || '')) return 'red';
      return null; // idle_prompt usw.: Status bleibt
    }
  }
  return null;
}

// Den Claude-Code-Prozess dieser Session suchen, damit die Ampel verschwindet,
// wenn das Terminal geschlossen wird. Kostet ~1s, passiert nur einmal pro Session.
// Native Installation: claude.exe. npm-Installation: node.exe mit ...claude-code...cli.js.
function findClaudeProcess() {
  const out = execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command',
    'Get-CimInstance Win32_Process | ForEach-Object { "$($_.ProcessId)|$($_.ParentProcessId)|$($_.Name)|$($_.CommandLine)" }'],
    { encoding: 'utf8', timeout: 10000, windowsHide: true });
  const procs = new Map();
  for (const line of out.split(/\r?\n/)) {
    const [pid, ppid, name, ...cmd] = line.split('|');
    if (name) procs.set(Number(pid), { ppid: Number(ppid), name, cmd: cmd.join('|') });
  }
  let pid = process.ppid;
  for (let i = 0; i < 25; i++) {
    const p = procs.get(pid);
    if (!p) break;
    const isClaude = /^claude(\.exe)?$/i.test(p.name) ||
      (/^node(\.exe)?$/i.test(p.name) && /claude-code[\\/].*cli\.m?js/i.test(p.cmd));
    if (isClaude) return { pid, pname: p.name.replace(/\.exe$/i, '') };
    pid = p.ppid;
  }
  return { pid: 0, pname: '' };
}

function main(e) {
  if (!e.session_id || e.agent_id) return; // nur der Haupt-Thread zählt
  const file = path.join(DIR, e.session_id.replace(/[^\w-]/g, '') + '.json');

  if (e.hook_event_name === 'SessionEnd') {
    try { fs.unlinkSync(file); } catch {}
    return;
  }

  let prev = null;
  try { prev = JSON.parse(fs.readFileSync(file, 'utf8')); } catch {}
  const state = stateFor(e, prev);
  if (!state && prev) return;

  const rec = {
    session_id: e.session_id,
    cwd: e.cwd || (prev && prev.cwd) || '',
    state: state || 'green',
    tool: e.tool_name || '',
    started: (prev && prev.started) || Date.now(),
    ts: Date.now(),
    pid: prev && prev.pid != null ? prev.pid : undefined,
    pname: (prev && prev.pname) || '',
  };
  if (rec.pid == null) {
    try { Object.assign(rec, findClaudeProcess()); } catch { rec.pid = 0; }
  }

  fs.mkdirSync(DIR, { recursive: true });
  const tmp = file + '.' + process.pid + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(rec));
  fs.renameSync(tmp, file);
}

let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', d => { raw += d; });
process.stdin.on('end', () => {
  try { main(JSON.parse(raw)); } catch {}
  process.exit(0);
});
