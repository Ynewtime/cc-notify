#!/usr/bin/env node
// merge-hooks.js -- Merge cc-notify hooks into Claude Code settings.json
//
// Usage: node merge-hooks.js <settings-path> <claude-dir> [--windows]

const fs = require("fs");
const path = require("path");

const MARKER = "terminal-status";

function buildHooks(claudeDir, windows) {
  if (windows) {
    const script = claudeDir + "\\terminal-status.ps1";
    const prefix =
      'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' +
      script +
      '" ';
    return {
      SessionStart: [
        { hooks: [{ type: "command", command: prefix + "reset" }] },
      ],
      UserPromptSubmit: [
        { hooks: [{ type: "command", command: prefix + "working" }] },
      ],
      PostToolUse: [
        {
          matcher: "AskUserQuestion|ExitPlanMode",
          hooks: [{ type: "command", command: prefix + "mark" }],
        },
      ],
      PermissionRequest: [
        {
          matcher: ".*",
          hooks: [{ type: "command", command: prefix + "alert" }],
        },
      ],
      Stop: [{ hooks: [{ type: "command", command: prefix + "done" }] }],
    };
  }

  const script = claudeDir + "/terminal-status.sh";
  return {
    SessionStart: [
      { hooks: [{ type: "command", command: script + " reset" }] },
    ],
    UserPromptSubmit: [
      { hooks: [{ type: "command", command: script + " working" }] },
    ],
    PostToolUse: [
      {
        matcher: "AskUserQuestion|ExitPlanMode",
        hooks: [{ type: "command", command: script + " mark" }],
      },
    ],
    PermissionRequest: [
      {
        matcher: ".*",
        hooks: [{ type: "command", command: script + " alert" }],
      },
    ],
    Stop: [{ hooks: [{ type: "command", command: script + " done" }] }],
  };
}

function isCcNotifyGroup(group) {
  return (
    group.hooks &&
    group.hooks.some((h) => h.command && h.command.includes(MARKER))
  );
}

function main() {
  const args = process.argv.slice(2);
  const windows = args.includes("--windows");
  const positional = args.filter((a) => !a.startsWith("--"));

  if (positional.length < 2) {
    console.error(
      "Usage: node merge-hooks.js <settings-path> <claude-dir> [--windows]"
    );
    process.exit(1);
  }

  const settingsPath = path.resolve(positional[0]);
  const claudeDir = positional[1];

  // Read existing settings
  let settings = {};
  if (fs.existsSync(settingsPath)) {
    const raw = fs.readFileSync(settingsPath, "utf8");
    try {
      settings = JSON.parse(raw);
    } catch (e) {
      console.error("  ERROR   Failed to parse " + settingsPath);
      console.error("          " + e.message);
      process.exit(1);
    }
  }

  // Build hooks for the target platform
  const newHooks = buildHooks(claudeDir, windows);

  if (!settings.hooks) {
    settings.hooks = {};
  }

  let count = 0;
  for (const [event, groups] of Object.entries(newHooks)) {
    if (!settings.hooks[event] || !Array.isArray(settings.hooks[event])) {
      settings.hooks[event] = groups;
    } else {
      const idx = settings.hooks[event].findIndex(isCcNotifyGroup);
      if (idx >= 0) {
        settings.hooks[event][idx] = groups[0];
      } else {
        settings.hooks[event].push(groups[0]);
      }
    }
    count++;
  }

  fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + "\n", "utf8");
  console.log("  config  Claude Code hooks ..... " + count + " events merged");
}

main();
