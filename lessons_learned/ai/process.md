---
name: process
description: Process rules covering pre-write verification sweeps, scaffold/bootstrap discipline, proof-of-concept-first feature development, and the lessons-learned cadence itself.
type: ai-subject
---

# Process — Subject Rules

Rules for *how* to work, not *what* to build. Anchor topics: verify-before-write sweeps, tool selection on Windows, scaffolding hygiene, and the lessons-learned discipline.

---

## Feature Development Order

### Proof of concept before full implementation

**When:** Starting any new feature — enrichment unit, detection flag, data source integration, scoring change, external API call.
**Rule:** Build the minimal version that proves the methodology works (or fails fast) *before* investing in error handling, config integration, logging, weights, and edge cases. A working 30-line PoC that confirms Cymru DNS resolves correctly in PowerShell is worth more than a 300-line production unit built on an assumption that turns out to be wrong. PoC criteria: the core mechanic executes end-to-end and returns a meaningful result on real data.

**PoC is not the same as a stub.** A stub returns a hardcoded value. A PoC hits the real data source / real API / real file path and returns real output. The PoC is the first regression test for the feature's fundamental feasibility.

**When the PoC passes:** add the production layer incrementally — logging, fallback, config wiring, weights entry, Tier 2 real-run verification. Each layer is a separate commit. The PoC result is the anchor: if a later layer breaks the core behavior, the PoC re-run exposes it immediately.

**When the PoC fails:** treat failure as early success — you learned the approach is wrong before building the full feature. Pivot the design before the investment compounds.

*Source: operator guideline 2026-04-10*

---

## Verify Before Writing

### Glob sweep before writing files into a new directory tree

**When:** Starting a phase that creates files in a new or sparsely-populated directory tree.
**Rule:** Run a single `Glob` over the target tree first to confirm current state. Catches in-progress work you might overwrite, surfaces leftover scaffold from a previous attempt, and excludes the "wait, this file already exists" class of bug. Costs <1s.

*Source: phase02_directory_scaffold.md#1*

---

### Validate JSON/YAML/TOML in the same step you write it

**When:** Hand-authoring a structured config file (JSON, YAML, TOML).
**Rule:** Round-trip parse it (`Get-Content | ConvertFrom-Json`, etc.) immediately after `Write` finishes. The cheapest moment to catch a typo is right after typing it. Same principle as parser-validation for `.ps1` and link-checking for `.md`.

*Source: phase03_config_files.md#1*

---

### "Already done" prior-phase files need re-verification when a current step depends on them

**When:** A planning doc says a file from a prior phase is "complete," but the current step depends on a specific property of that file.
**Rule:** Re-read it. Prior-phase "complete" labels are not load-bearing. Verify the property the current step depends on is actually present, not just that the file exists.

*Source: phase03_config_files.md#3*

---

### When two planning docs disagree, read the committed file then reconcile

**When:** Mid-phase, two planning docs describe the same file's contents differently.
**Rule:** Read the committed file (ground truth), then update the wrong plan(s) to match. Label the winner by role: tactical doc wins for implementation details, strategic doc wins for architecture. See also: docs.md "When two planning docs disagree about a file, read the committed file."

*Source: phase03_config_files.md#2*

---

## Scaffolding & Tools

### Prefer Write at nested paths over Bash mkdir on Windows

**When:** Creating a new directory tree on Windows.
**Rule:** Use `Write` with the full nested path — directory creation is implicit. Avoids bash/PowerShell shell portability concerns and quoting around paths with spaces. Only fall back to a `mkdir` Bash call if the directory must be empty (use `.gitkeep` instead).

*Source: phase02_directory_scaffold.md#2*

---

### .gitkeep for transient empty dirs; READMEs only when guidance is load-bearing

**When:** Creating an empty directory that needs to exist in git (`output/`, `iocs/`, `logs/`).
**Rule:** Use a `.gitkeep` file. Reserve per-directory `README.md` for folders where operator guidance — file conventions, naming, security — is genuinely load-bearing. Empty README scaffolds rot.

*Source: phase02_directory_scaffold.md#3*

---

## Lessons-Learned Cadence

### On bootstrap phases, keep Applied Lessons table with a placeholder row

**When:** Writing the very first phase reflection (no prior phases to apply lessons from).
**Rule:** Keep the `Applied Lessons` table with one placeholder row (`| (none -- first phase) | -- | -- |`). Don't silently drop format sections. The cadence *is* the discipline.

*Source: phase01_doc_realignment.md#3*

---

### Bug-fix reflections must answer "what would have caught this?"

**When:** Writing a reflection on a hot-fix or post-ship bug.
**Rule:** The reflection's primary question is not "what was the bug" (that's the commit message) but "what verification step *would have* excluded this bug class, and where does it now belong?" Encode the answer as a Carry-Forward against the verification plan, not as a code comment. The bug is one data point; the gap in coverage is the durable lesson.

*Source: phase11_ps51_encoding_fix.md#1, phase12_diagnostic_playbook.md#step13*

---

### Read peer code from adjacent forensics/security domains for techniques, not for use cases

**When:** The operator (or a colleague) shares code from a related forensics, IR, or security tool — even if it's a different language, different artifact type, or different problem.
**Rule:** Read it for *techniques*, not for use cases. Trade knowledge — Team Cymru DNS lookups, sigcheck signer extraction, PE-header beaconing patterns — is invisible to general documentation but visible in working code from practitioners. The technique usually ports across language and use case even when the surrounding code does not. Cost: 5 minutes to read 200 lines of peer code. Value: months of avoided wrong-direction work when the technique collapses a previously-deferred phase boundary. When uncertain whether the script will help, default to reading it.

*Source: phase13_external_pattern_borrow.md#finding5*

---

### Carry-forwards must record their premise, not just their deferral

**When:** Writing a Carry-Forward (CF) entry that defers work to a future phase or release.
**Rule:** Write the *premise* of the deferral, not just the deferral. "Deferred to Phase 2 *because* requires offline DB" is reviewable; "Deferred to Phase 2" is opaque and outlives its premise silently. On every phase boundary, walk open CFs and re-test each premise against current knowledge — premises decay (a peer script may eliminate the offline DB requirement), and a CF whose premise has fallen should be promoted into the active plan immediately, not on its original schedule. Symptom you missed this: a CF you wrote months ago that turns out to be trivially solvable today.

*Source: phase13_external_pattern_borrow.md#finding6*

---

## Diagnostic Playbook

Generalized debugging steps from phase12. Apply in order when triaging an unfamiliar failure. Steps 8 and 11 (encoding-specific tooling, parser/JSON validators) live in [powershell.md](powershell.md) and [config.md](config.md) respectively.

### Read the entire error transcript verbatim before forming a hypothesis

**When:** A user (or tool) pastes a multi-line error report.
**Rule:** Read every line of the transcript, not just the cited line number. The cited line is often downstream noise; the smoking gun is usually quoted elsewhere in the message — in echoed source text, in a "near here" hint, in a stderr line above the stack trace. Skipping to the line number is the fastest way to chase a symptom instead of the cause.

*Source: phase12_diagnostic_playbook.md#step1*

---

### Force the hypothesis into one sentence before running any diagnostic

**When:** You think you know what the bug is and are about to start investigating.
**Rule:** Write the hypothesis as a single sentence: "X is happening because Y, evidenced by Z." If you can't, you don't have a hypothesis — you have a hunch, and your diagnostics will wander. The sentence is a contract: it tells you what evidence would falsify it.

*Source: phase12_diagnostic_playbook.md#step3*

---

### Use a ground-truth tool that bypasses the broken layer

**When:** You suspect a tool is misreporting because of the very bug you're investigating.
**Rule:** Reach for a tool one level below the broken layer — raw bytes when text is suspect, AST parser when the interpreter cascades, hex dump when the editor lies. The diagnostic must not depend on the same machinery that's failing. (For PowerShell encoding bugs specifically: `[System.IO.File]::ReadAllBytes` — see powershell.md.)

*Source: phase12_diagnostic_playbook.md#step4*

---

### Stop and switch tools when the diagnostic environment is itself compromised

**When:** Your diagnostic command returns a confusing error that doesn't match the bug you're chasing.
**Rule:** Suspect the diagnostic environment, not the target. Bash mangling backslashes, a shell stripping quotes, an IDE re-saving a file mid-investigation — these create false-positive bugs that waste rounds. Switch to a more direct path (write a script file, run from a fresh shell, use a hex viewer) before continuing. See also: powershell.md "Never cram multi-line pwsh into bash-quoted -Command."

*Source: phase12_diagnostic_playbook.md#step5*

---

### Quantify the bug's blast radius before fixing it

**When:** You've confirmed a bug class and are about to write the fix.
**Rule:** Enumerate every instance first — how many files, how many bytes, how many distinct codepoints/patterns/call sites. The bounded count tells you whether to write a deterministic substitution map (small, named set) or a structural refactor (open-ended). It also gives you the verification target: "after fix, count == 0." Skipping this step makes greedy strip-and-replace tempting and irreversible.

*Source: phase12_diagnostic_playbook.md#step6*

---

### Bounded substitution maps over greedy strip-and-replace

**When:** Bulk-fixing a pattern across multiple files.
**Rule:** Write an explicit map (`{ pattern1: replacement1; pattern2: replacement2 }`) covering exactly the codepoints/strings the audit found. Auditable, reversible, defensible in review. `[regex]::Replace($text, '[\u0080-\uFFFF]', '?')` erases information you may need later. The map is a manifest of intent.

*Source: phase12_diagnostic_playbook.md#step7*

---

### The discovery tool IS the first regression test

**When:** You wrote a script to find a bug and you're about to write a separate verification script.
**Rule:** Don't. Re-run the discovery tool against the post-fix state and assert count == 0. Same code path, same assumptions, same edge cases — that's the point. Building a separate verifier risks the verifier missing a case the discoverer caught.

*Source: phase12_diagnostic_playbook.md#step9*

---

### Cross-check fixes with a tool from a different tool class

**When:** Your same-tool re-run shows the bug is gone.
**Rule:** Verify with a tool of a different class before declaring done — if you found it with a byte audit, verify with a parser; if you found it with a parser, verify with a functional run. Same-class verification can share blind spots; cross-class verification can't. Stop only when both agree.

*Source: phase12_diagnostic_playbook.md#step10*

---

### After a fix, ask "what is the bug class and where else can it manifest?"

**When:** You've fixed the reported instance and verified it's gone.
**Rule:** Don't stop. Generalize the bug to its class ("UTF-8-without-BOM in any text file PS 5.1 reads," not "em-dashes in Deploy.ps1"), then audit every file in scope of that class. The reported instance is one symptom; the fix scope is the whole class. Scope expansion now beats a round-2 hot-fix later.

*Source: phase12_diagnostic_playbook.md#step12*

---
