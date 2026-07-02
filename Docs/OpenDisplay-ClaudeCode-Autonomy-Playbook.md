# OpenDisplay — Claude Code Autonomy Playbook

How to hand Batch 1 (and later batches) to Claude Code so it keeps shipping features with minimal
intervention — adapted to OpenDisplay's specifics, not generic loop advice. Built from Anthropic's
current Claude Code best-practices guidance plus the 2026 "loop engineering" community practice
(Boris Cherny: *"my job is to write loops"*; Geoffrey Huntley's Ralph technique).

---

## 0. The model in one paragraph

An autonomous run is a **doer + checker** loop, not a big prompt. A *doer* makes a change; a *checker*
that the doer can't fake decides if it's done; the loop repeats until the check passes, then stops
itself. Three things make it work: a **machine-checkable definition of done**, a **fresh context each
iteration** (so the context window doesn't fill and degrade), and **external memory on disk** (so the
fresh context knows what's already done). The single most important rule, straight from Anthropic:
**give Claude a check it can run.** Everything below is in service of that.

OpenDisplay is an unusually *good* fit for this because it already has three verification layers most
projects lack — see §2.

---

## 1. ⚠️ The one hazard unique to OpenDisplay — read this first

**The loop runs on the same Mac whose displays it modifies.** Several Batch 1 features
(auto-disconnect built-in #5, resolution slider #2, the arrangement-safety work #6) can, if executed
*for real* against the live desktop, blank or strand the very display this session is being watched
on — and the audit already found that resolution/mirror/set-main bypass the SafetyEngine, so a bad
real resolution can blank the only panel.

**The rule that follows:** the autonomous loop verifies **logic**, never **live hardware mutation.**
This is cheap for you because the architecture already separates them:

- The disconnect/scene/resolution/safety **logic** is covered by `make test` (78 tests) against the
  `SimulatorProvider` (in-memory, fault-injecting). The loop can fully exercise these features
  **without touching a real display.**
- **Real-hardware verification** (actually disconnecting a panel, applying a real mode, reading the
  monitor back over the control MCP) is reserved for **attended** runs, ideally on a **secondary /
  test display** rather than the primary panel — and never on the rescue/recovery path.

So: let the loop run free on the *tested core + CLI surface*; keep the destructive real-display checks
for when you're watching. The safety hook in §4 enforces this.

---

## 2. Your verification ladder (lean on it — it's your biggest advantage)

| Layer | What it proves | Use in the loop? |
|---|---|---|
| `make test` (78 unit/state-machine tests, `SimulatorProvider`) | Feature **logic** is correct, deterministically, with no hardware | **Yes — primary gate.** Every iteration ends here. |
| `opendisplay … --json` CLI read-back | Behavior through the real command surface (set X → read X back) | **Yes**, for non-destructive reads (brightness/info/state). Gate destructive verbs behind attended runs. |
| Monitor-control MCP (read real display state) | The change actually took effect on hardware | **Attended only** — and reads, not destructive writes, when unattended. |

Each Batch 1 issue already ends with a test step. **For the loop, the completion gate is: that
issue's new/updated tests pass under `make test`, green, exit 0.** "Looks done" is not a signal; the
green suite is.

> Note: there is **no remote CI** in the repo today — `make test` is the gate, run locally. If you
> want PR-based loops (§5, option C), add a tiny GitHub Action that runs `make test` on the
> cross-platform packages (they build on Linux per the README), giving the loop a remote green check
> for the non-macOS work. The macOS-hardware bits still verify locally/attended.

---

## 3. Externalize memory (the trick every long run depends on)

Keep a `PROGRESS.md` at the repo root, committed each iteration. The fresh-context iteration reads it
and knows what to do next. Minimum shape:

```markdown
# OpenDisplay autonomous progress
## Done
- (none yet)
## In progress
- Issue 1 (DDC power 0xD6): writing the Feature case + CLI verb
## Tried / failed (so the next pass doesn't repeat it)
- (none yet)
## Next (Batch 1 order)
1 → 2+6 → 3 → 4 → 5
```

This is what stops the loop from going in circles after a context reset — *the agent forgets, the repo
doesn't.* The Batch 1 issues doc is the spec; `PROGRESS.md` is the running state.

---

## 4. One-time setup

### a) CLAUDE.md (merge these into your existing one)

Keep it short — Anthropic's guidance is that a bloated CLAUDE.md gets *ignored*. The high-value lines
for autonomy here:

```markdown
# Build & verify
- Test gate: `make test` (78 tests). Code is not done until this is green, exit 0.
- Also: `make lint` (SwiftLint), `make xcode` (regen project), `swift build`.
- Show evidence (test output / CLI JSON), never assert "done" without it. Fix root causes.

# Platform
- Apple Silicon only. No Intel. Private SPI stays behind `#if !PUBLIC_API_ONLY` + dlsym.

# SAFETY — non-negotiable during unattended runs
- NEVER execute real display disconnect/reconnect, resolution/mirror/set-main changes, or blackout
  against the live desktop. Verify that logic via `make test` (SimulatorProvider) and non-destructive
  `opendisplay --json` reads ONLY.
- NEVER modify the rescue app or recovery path as part of feature work without explicit approval.
- Gated ops route through TopologyCoordinator/SafetyEngine.

# Boundaries
- Clean-room: no BetterDisplay code, assets, UI, or copy. Implement from public docs / first
  principles.
- One Batch 1 issue at a time. Branch per issue. Commit only when `make test` is green. Update
  PROGRESS.md every iteration.

# Context hygiene
- Pipe verbose build/test output to a file and grep failures; don't dump full logs into context.
- On compaction, preserve: the current issue, the list of modified files, and the test command.
```

(Run `/init` first if you don't have one, then prune to the above.)

### b) A reviewer subagent (the "checker" that isn't the "doer")

`.claude/agents/parity-reviewer.md` — reviews each issue's diff in a **fresh context** against its
acceptance criteria. Tell it to flag **only correctness/requirements gaps, not style** (a reviewer
asked for gaps invents them; chasing all of them causes over-engineering — especially tempting in a
safety-conscious codebase):

```markdown
---
name: parity-reviewer
description: Reviews a Batch 1 issue diff against its acceptance criteria
tools: Read, Grep, Glob, Bash
model: opus
---
Review the current diff against the named issue's acceptance criteria. Confirm: every criterion is
implemented; the new tests actually cover them; nothing outside the issue's scope changed; SAFETY
rules in CLAUDE.md are respected (no live-hardware mutation paths added to unattended flows). Report
only gaps affecting correctness or the stated requirements. Ignore style.
```

Anthropic also ships a bundled `/code-review` skill that does a fresh-context correctness review of
the diff — fine to use instead.

### c) A PreToolUse safety hook (enforces §1 deterministically)

Hooks are deterministic where CLAUDE.md is only advisory. Have Claude write one
(*"write a PreToolUse Bash hook that blocks `opendisplay disconnect|reconnect|scene apply|blackout`
and any real display-reconfiguration command when running non-interactively"*). This guarantees the
loop can't yank a live display even if a prompt drifts.

### d) Permissions posture

Use **auto mode**, not blanket bypass:

```bash
claude --permission-mode auto -p "…"
```

A classifier blocks scope-escalation/risky actions and lets routine work through; on `-p` runs it
**aborts if it keeps blocking** (fails safe — good). Allowlist the safe surface so it doesn't stall:
`Edit`, `Bash(make *)`, `Bash(swift *)`, `Bash(git *)`, `Bash(gh *)`. **Do not** hand a host-display
session `--dangerously-skip-permissions` given §1.

---

## 5. Running the loop

A single Claude run stops when it thinks it's done. To keep it going you need the **Stop-hook +
completion-promise** pattern. Three ways, simplest first:

**Option A — Ralph Wiggum plugin (recommended start).** Widely reported as an official Anthropic
plugin; it installs the Stop hook that re-feeds the task with fresh context until a promise marker
appears.

```bash
/plugin marketplace add anthropics/claude-code
/plugin install ralph-wiggum@claude-plugin

/ralph-loop "Implement Issue 1 from docs/OpenDisplay-Issues-Batch-1.md. Run `make test`. When that
issue's tests pass green and its acceptance criteria are met, output <promise>DONE</promise>. Update
PROGRESS.md." --max-iterations 10 --completion-promise "DONE"
```

Start with **one issue and `--max-iterations 10`** to calibrate cost/behavior, watch the first run,
then scale up.

**Option B — transparent bash fallback** (same idea, full visibility):

```bash
while :; do
  claude -p "$(cat docs/OpenDisplay-Issues-Batch-1.md | sed -n '/Issue 1 —/,/Issue 2 —/p'). \
Run make test. When this issue's tests pass green and acceptance criteria are met, output \
<promise>DONE</promise>. Append progress to PROGRESS.md." \
    --permission-mode auto \
    --allowedTools "Edit,Bash(make *),Bash(swift *),Bash(git *),Bash(gh *)" \
    --max-turns 30 \
  | tee -a loop.log
  grep -q "<promise>DONE</promise>" loop.log && break
done
```

**Option C — PR-per-iteration** (if you add the Linux CI from §2): each iteration branches, commits,
opens a PR via `gh`, waits for the `make test` check, and you (or an agent-team lead) merge. This
keeps every change reviewable and respects branch protections.

**Per-issue protocol** (whichever option): one issue → branch → implement → `make test` green →
`parity-reviewer` subagent on the diff → fix gaps → commit → update `PROGRESS.md` → next issue.
**Checkpoint per issue** — don't hand all six at once; a failure in #4 shouldn't burn the tokens of
#5–6. Batch 1's order (1 → 2+6 → 3 → 4 → 5) is already set.

> On Opus 4.8 the Ralph loop is less *necessary* than it was — the model follows a plan and manages
> context far better, so well-specified small issues like these often converge in one or two passes.
> Reach for the loop when an issue needs several attempts, not by default.

---

## 6. Cost & runaway guardrails (the $6k-overnight lesson)

The headline cautionary tale: a Reddit user's 30-minute scheduled loop with no real stop condition ran
up ~$6,000 overnight — because a short cache TTL meant an 800k-token context was rebuilt from scratch
48×/day. Avoid that:

- **Cap iterations.** `--max-iterations` (plugin) / `--max-turns` (CLI). Start at 10–15.
- **Hard money ceiling.** Settings → Usage → set a monthly spend cap (or a workspace spend limit in
  the Console on API). Enable **task budgets** (beta) for a soft per-workflow boundary.
- **Keep loops tight, not scheduled-with-gaps.** Back-to-back iterations reuse the prompt cache;
  long sleeps between wake-ups blow it away and re-bill the whole context. Don't put these small
  issues on a 30-minute timer.
- **A real stop condition every time** = the `<promise>` marker gated on green tests. Never "run until
  it feels done."
- **Context hygiene** (the real reason overnight runs die — they run out of *context*, not time):
  fresh context per iteration (Ralph does this), suppress verbose logs, lean CLAUDE.md.

These issues are small (hours to half-a-day each) and gated by a fast deterministic suite, so they
converge cheaply — far lower risk than open-ended refactors. The danger scales with how open-ended
the task is, which is exactly why we pre-cut them into tight specs.

---

## 7. What stays human-in-the-loop

Resist the fully-unattended "dark factory." Keep yourself in the loop for:

- **Real-hardware verification** of the destructive display features (§1) — attended, on a test panel.
- **Merging to main** (or at least a spot-check of the recorded reviewer findings).
- **The Tier 3/5 moat** later (flexible scaling, XDR/HDR, virtual screens, EDID override): these touch
  private SPI and real display state and are poor first candidates for hands-off loops.
- **Anything that would modify the rescue/recovery path.**

The greenfield-but-self-contained Batch 1 items (DDC power, prevent-sleep, URL scheme) and the
logic-testable ones are the safe autonomy targets. Start there.

---

## 8. Advanced (optional, later)

For running the *whole batch* hands-off rather than issue-by-issue, Opus 4.8's **Dynamic Workflows**
(research preview) moves the orchestration plan into a background JavaScript script instead of the
context window — which is the constraint that breaks long multi-task runs. Worth a look once the
per-issue Ralph loop is working reliably; it's the more advanced path, not the starting point.

---

### Sources
Anthropic Claude Code best-practices & hooks docs (the verification rule, `/goal`, Stop-hook 8-block
override, auto mode, subagents, `claude -p`); community "loop engineering" writing (Cherny, Huntley/
Ralph, Osmani); the $6k-overnight and cache-TTL reports; Ralph Wiggum plugin write-ups. Verify command
names against your installed Claude Code version — the surface is moving fast.
