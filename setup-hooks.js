// Adds the Ampel hooks to the Claude Code settings or removes them again.
//   node setup-hooks.js install
//   node setup-hooks.js uninstall
// Other hooks in settings.json stay untouched. A backup is created before every change.
const fs = require('fs');
const path = require('path');
const os = require('os');

const mode = process.argv[2];
if (mode !== 'install' && mode !== 'uninstall') {
  console.error('Usage: node setup-hooks.js install|uninstall');
  process.exit(2);
}

const configDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const file = path.join(configDir, 'settings.json');
const hookScript = path.join(__dirname, 'hook.js').replace(/\\/g, '/');
const command = `node "${hookScript}"`;

// Event -> needs a matcher (tool events)
const EVENTS = {
  SessionStart: false,
  SessionEnd: false,
  UserPromptSubmit: false,
  Stop: false,
  Notification: false,
  PreToolUse: true,
  PostToolUse: true,
  PostToolUseFailure: true,
  PermissionRequest: true,
};

const isAmpelHook = h => typeof h.command === 'string' && /claude-ampel[\\/][^"]*hook\.js/i.test(h.command);

let settings = {};
let original = null;
if (fs.existsSync(file)) {
  original = fs.readFileSync(file, 'utf8');
  try {
    settings = original.trim() ? JSON.parse(original) : {};
  } catch (err) {
    console.error(`${file} is not valid JSON (${err.message}). Nothing changed.`);
    process.exit(1);
  }
}

// Remove existing Ampel entries (including from an earlier install location)
const hooks = settings.hooks || {};
for (const ev of Object.keys(hooks)) {
  if (!Array.isArray(hooks[ev])) continue;
  hooks[ev] = hooks[ev]
    .map(g => (Array.isArray(g.hooks) ? { ...g, hooks: g.hooks.filter(h => !isAmpelHook(h)) } : g))
    .filter(g => !Array.isArray(g.hooks) || g.hooks.length > 0);
  if (hooks[ev].length === 0) delete hooks[ev];
}

if (mode === 'install') {
  for (const [ev, needsMatcher] of Object.entries(EVENTS)) {
    const entry = [{ type: 'command', command, timeout: 15 }];
    (hooks[ev] = hooks[ev] || []).push(needsMatcher ? { matcher: '*', hooks: entry } : { hooks: entry });
  }
}

if (Object.keys(hooks).length) settings.hooks = hooks;
else delete settings.hooks;

const out = JSON.stringify(settings, null, 2) + '\n';
if (original !== null && out === original) {
  console.log('Hooks are already up to date.');
  process.exit(0);
}

fs.mkdirSync(configDir, { recursive: true });
if (original !== null) {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  fs.writeFileSync(`${file}.bak-ampel-${stamp}`, original);
}
fs.writeFileSync(file, out);
console.log(mode === 'install' ? `Hooks added to ${file}` : `Hooks removed from ${file}`);
