/Human generated text: 
Simple to use just ask Claude to use the Bionic LLM Subagent to help during tasks and it will find it a job to do. 
Tips: Pick a small fast model. 
If it fails be sure to look at what model Claude is trying to talk to in Bionic you can always tell it you're using a different one. 
Output will be slow unless you have a fast machine Claude will determine a good task. 
/end of human generated text.


# Bionic Claude

Lets Claude Code delegate coding subtasks to a local LLM running on your machine via
**LM Studio** (the engine behind the "Bionic" desktop app), so routine work — boilerplate,
first drafts, mechanical refactors, routine tests — can run offline and in parallel with
Claude's own work.

This package contains everything needed to install the skill and the configuration app
on a fresh machine, or to reinstall/back up your current setup.

---

## What's in this package

```
BionicClaude/
├── Install.ps1        <- run this to install
├── Uninstall.ps1       <- run this to remove everything
├── README.md           <- this file
└── skill/
    ├── SKILL.md                       <- the skill Claude Code reads
    └── scripts/
        ├── Subagent-BionicClaude.ps1  <- the config/control GUI
        ├── bionic-ask.ps1             <- what Claude Code actually calls
        ├── BionicConfig.psm1          <- shared settings module
        └── Launch-BionicClaude.vbs    <- launches the GUI without a console window
```

---

## Prerequisites

1. **Windows** with PowerShell 5.1+ (built in on Windows 10/11).
2. **[LM Studio](https://lmstudio.ai)** installed — this provides the `lms` CLI and the
   local model server that actually runs the LLM. You don't need LM Studio's own window
   open; its background server does the work.
3. **Claude Code** installed and set up on this machine.

You don't need any model downloaded yet — the config app can download one for you.

---

## Installing

1. Open a PowerShell window in this folder (or right-click `Install.ps1` and choose
   "Run with PowerShell").
2. If double-clicking doesn't work due to execution policy, run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File Install.ps1
   ```

3. The installer will:
   - Check that LM Studio's `lms` CLI is present (warns, but doesn't block, if it isn't
     installed yet — you can install LM Studio afterward and everything will just work).
   - Copy the skill into `%USERPROFILE%\.claude\skills\bionic`, which is where Claude
     Code looks for skills.
   - Create a **config.json** and **transcript.log** in that folder if they don't
     already exist (existing ones from a previous install are never overwritten, so
     your saved defaults and activity history survive a reinstall).
   - Create a **"Subagent BionicClaude"** shortcut on your Desktop.

Re-running the installer later (e.g. after you update the files in this package) is
safe — it refreshes the scripts and `SKILL.md` but leaves your settings and transcript
alone.

---

## First-time setup

1. Double-click the **Subagent BionicClaude** shortcut on your Desktop.
2. Click **Start Server** (top section). The status label turns green once LM Studio's
   server is up.
3. In the **Installed Models** list:
   - If you already have models downloaded in LM Studio, select one and click
     **Load Selected**.
   - Otherwise click **Download New...** and enter a model name or search term (e.g.
     `qwen coder` or a full identifier like `qwen/qwen2.5-coder-7b-instruct`). The
     download streams progress into the log and can be cancelled mid-way.
4. In the **Defaults** section, optionally set a default model, port, temperature, and
   max tokens, then click **Save Settings**. Claude Code's calls to `bionic-ask.ps1`
   pick these up automatically for anything you don't explicitly override.
5. Leave the window open (or reopen it any time) to watch the **Bionic Activity** panel
   at the bottom — a black-background, green-text terminal that live-updates with every
   task Claude sends to the local model and what it replies. Click **Clear** to wipe it.

---

## Using it from Claude Code

You don't need to do anything special — the skill's description tells Claude Code to use
it proactively for well-scoped, mechanical coding subtasks (boilerplate, first drafts,
routine tests, mechanical refactors), and any time you explicitly say things like
"ask Bionic to ..." or "use the local model for ...".

Under the hood, Claude Code runs:

```powershell
powershell -File "%USERPROFILE%\.claude\skills\bionic\scripts\bionic-ask.ps1" -Task "<description>" -Files @("path\to\file.py")
```

The local model has no filesystem access — it only sees whatever file contents are
passed in `-Files`, and can only propose changes back as text (Claude reviews and
applies them, it never writes to disk on the local model's say-so).

---

## The config app, section by section

**LM Studio Server** — Start/Stop the local model server, and Refresh Status to see if
it's running and on which port.

**Installed Models** — Everything you've downloaded via LM Studio.
- **Load Selected** / **Unload Selected** — manage what's resident in memory. Only one
  model is ever kept loaded at a time; loading a new one automatically unloads whatever
  else was loaded first (loading a model that's already loaded is a no-op, not a
  duplicate).
- **Unload All** — safety-net button to clear everything out of memory at once.
- **Download New...** — fetch a new model by name or search term, with live progress
  and a cancel button.

**Defaults used by the Bionic skill** — the model, port, temperature, and max-token
settings `bionic-ask.ps1` falls back to when Claude Code doesn't pass them explicitly.

**Bionic Activity** — the black/green terminal panel showing a live transcript of every
task sent to the local model and its response, tailing `transcript.log`. Purely
read-only and for visibility; it doesn't affect anything. Use **Clear** to wipe it.

---

## Troubleshooting

**"Model not found" when loading** — LM Studio sometimes lists a model with a
`(N variant)` suffix (e.g. `qwen/qwen3.8-27b (1 variant)`). The installed scripts
already strip this automatically; if you ever see this error, it means the scripts in
your live install are out of date — re-run `Install.ps1` from this package.

**Multiple copies of the same model showing as loaded** — this used to happen because
loading an already-loaded model created a second in-memory instance instead of reusing
it. Fixed: the scripts in this package always check what's loaded first and unload
anything else before loading something new, so there's only ever one model resident.
If you still see duplicates from before this fix, click **Unload All** once to clear
them out.

**Server won't start** — check LM Studio is actually installed (`%USERPROFILE%\.cache\lm-studio\bin\lms.exe`
should exist) and that nothing else is using port 1234 (change the port in Defaults if
it is).

**Claude Code isn't using the skill** — confirm the skill is in
`%USERPROFILE%\.claude\skills\bionic\SKILL.md` (re-run `Install.ps1` if not) and that
Claude Code has been restarted since installing.

---

## Uninstalling

Run `Uninstall.ps1` the same way you ran the installer. It removes the skill folder
(including your saved settings and activity log) and the desktop shortcut. It does not
touch LM Studio itself or any models you've downloaded — those are managed independently
by LM Studio.

---

## Why this exists instead of automating the "Bionic" app directly

The Bionic desktop app itself is a plain Electron GUI with no CLI, API, or IPC surface —
there's nothing to script against it. The model it runs sits on top of LM Studio's own
runtime, which does expose a scriptable `lms` CLI and a local OpenAI-compatible REST API
once its server is started. This skill talks to that server directly, so you don't even
need the Bionic app window open — LM Studio's background server is the actual engine.
