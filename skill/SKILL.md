---
name: bionic
description: Delegate a coding subtask to the user's local LLM running via LM Studio (the same engine that powers the "Bionic" desktop app) as a subagent, without needing to be asked by name. Use this proactively — not just when the user says "ask Bionic" or "use the local model" — whenever a piece of work is well-scoped and independent enough to hand off: generating boilerplate, a first draft of a script/function, writing routine tests, doing a mechanical refactor/rename pass, or any chunk of coding work that could run in parallel with what Claude is doing directly. Also use it whenever the user wants a second opinion from an offline/local model, wants to keep a task fully offline/private, is comparing local-model output against Claude's own, or explicitly mentions Bionic, LM Studio, or "my local model." Do not use it for work that needs strong reasoning, full codebase context, or careful judgment — the local model is much smaller than Claude and is best suited for narrow, mechanical subtasks, not as a wholesale replacement for Claude's own work.
---

# Bionic (local LLM subagent via LM Studio)

## What this actually talks to

The user has a desktop app called **Bionic**, made by LM Studio, for running LLMs locally.
Bionic itself is a GUI-only Electron app with no CLI or API — there is nothing to script
against it directly. But the model it runs sits on top of **LM Studio's own runtime**, which
*does* expose a scriptable interface:

- `lms` CLI at `%USERPROFILE%\.cache\lm-studio\bin\lms.exe` — lists/loads/unloads models,
  starts/stops a local server.
- That server exposes a normal **OpenAI-compatible REST API** (default `http://127.0.0.1:1234`)
  once started.

So "ask Bionic" in practice means: make sure a model is loaded in LM Studio, and send it the
task over that local REST API. The user does not need Bionic.exe running at all for this to
work — LM Studio's own server is the actual engine.

## Configuration panel

There's a clickable config app, **"Subagent BionicClaude"** (desktop shortcut, or run
`scripts\Subagent-BionicClaude.ps1` directly), where the user sets: which model to use by
default, the server port, temperature, and max tokens, plus buttons to start/stop the server
and load/unload/download models. Settings saved there land in `config.json` next to this
SKILL.md, and `bionic-ask.ps1` reads that file automatically for any parameter not explicitly
passed on the command line — so if the user says "I changed the default model in the panel,"
you don't need to pass `-Model` yourself, it'll already pick up the new default.

## Activity panel

The Subagent BionicClaude config panel has a built-in black-background/green-text terminal
section at the bottom labeled "Bionic Activity - live subagent transcript." It auto-refreshes
every second and shows what's being sent to the local model and what it replies, in near real
time. Every call to `bionic-ask.ps1` appends the task, files, and full response to
`transcript.log` next to this SKILL.md; the panel just tails that file. You don't need to do
anything extra for this to work — it's automatic as long as you invoke the local model through
`bionic-ask.ps1` as documented below.

## How to use it

Run the bundled script for every request to the local model — don't hand-roll `Invoke-RestMethod`
calls, since the script already handles starting the server and picking a loaded model:

```powershell
powershell -File "C:\Users\John\.claude\skills\bionic\scripts\bionic-ask.ps1" -Task "<what you want it to do>" -Files @("path\to\file1.py","path\to\file2.py")
```

Parameters:
- `-Task` (required) — plain-language description of the subtask. Be specific; this model is
  smaller than you and does better with a narrow, concrete ask than an open-ended one.
- `-Files` (optional) — array of file paths to give as context. The script reads and embeds
  their contents; the local model cannot read the filesystem itself.
- `-Model` (optional) — an LM Studio model identifier (see `lms ls` for what's on disk). If
  omitted, the script uses whatever model LM Studio's server currently reports as loaded — note
  that starting the server (which this script does automatically if it's down) can drop
  whatever the GUI had loaded, so don't assume a specific model is active without checking.
  `deepseek-coder-6.7b-instruct` is installed on this machine and is a good default for
  code-generation-heavy asks; consider passing `-Model deepseek-coder-6.7b-instruct` explicitly
  and mention to the user that you did so.
- `-Temperature`, `-MaxTokens` (optional) — tune if the default (0.2 / 4096) doesn't fit the task.

The script prints the model's raw response to stdout. Read that output yourself before doing
anything with it — treat it the same way you'd treat a suggestion from any other subagent:
useful signal, not something to blindly trust.

## Applying results — always review first

The local model has no filesystem access; it can only propose text back to you. When it proposes
a full file's contents, it prefixes the block with a line like:

```
FILE: path\to\file.py
```

followed by a fenced code block with the new contents.

**Do not write these changes to disk automatically.** Show the user what the local model
proposed (a summary, or the diff against the current file) and get their go-ahead before you
apply it with your own Edit/Write tools. This mirrors how you'd handle output from any other
subagent whose judgment hasn't been vetted — the local model is smaller and more error-prone
than you, so treat its output as a draft, not a patch.

If the user just wants an opinion, explanation, or second take rather than a file edit, there's
nothing to apply — just relay what it said.

These are small models (7-8B parameters) running locally, and in testing they sometimes keep
generating past a clean answer — echoing training-format artifacts, fake follow-up turns, or
restating the prompt back. Read to the end, pull out the actual answer, and don't just forward
the raw output verbatim to the user; trim the noise the way you would clean up any messy
subagent response.

## When the server or model isn't ready

The script already handles the common cases (starting the server if it's down, using whatever
model is loaded if `-Model` isn't given), and will error out with a clear message + suggested
fix if nothing is loaded and no model was specified. If that happens, tell the user what
happened and either ask which model to use or offer to load one yourself with:

```powershell
& "$env:USERPROFILE\.cache\lm-studio\bin\lms.exe" load <model-name>
```

Run `& "$env:USERPROFILE\.cache\lm-studio\bin\lms.exe" ls` to see what's installed.

## Why not automate the Bionic GUI itself

It was tempting to drive Bionic.exe directly, but it's a plain Electron app with no IPC,
CLI, or HTTP surface exposed for automation — its only open port returns 404 on every route.
UI-automation (simulating clicks/keystrokes in the Electron window) would be fragile and is not
worth the complexity when the same model is reachable cleanly through LM Studio's own server.
If a future LM Studio/Bionic release adds a real API, this skill should be updated to use it.
