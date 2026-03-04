// Extract toast message from Claude Code hook data.
// Usage: node toast-extract.js <action> <hook-data.json>
//   action: "done" | "notify"
const fs = require("fs");

try {
  const action = process.argv[2] || "done";
  const j = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
  const cwd = j.cwd || "";
  const segments = cwd.split(/[/\\]/).filter(Boolean);
  const project = segments.slice(-2).join("/") || "~";

  if (action === "notify") {
    process.stdout.write(project + " \xb7 \u7b49\u5f85\u51b3\u7b56");
  } else {
    process.stdout.write(project + " \xb7 \u5b8c\u6210");
  }
} catch {
  process.stdout.write("Task completed");
}
