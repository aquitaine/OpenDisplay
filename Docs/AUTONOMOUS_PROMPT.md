You are working autonomously on OpenDisplay (an Apple-Silicon-only macOS display manager) while I'm
away for several hours. Build through the Batch 1 issues, verify each with the test suite, and commit
green work as you go. Work safely and do not burn budget on dead ends.

# Setup
- Spec: read `docs/OpenDisplay-Issues-Batch-1.md` — six issues, each with acceptance criteria,
  file/symbol pointers, and test steps.
- State: read `PROGRESS.md` first to see what's done, and update it after every issue.
- Branch: work on `batch1-auto` (create it if needed). Commit per issue. Do NOT push or open PRs.

# SAFETY — hard rules, no exceptions
- This session runs on the same Mac whose displays the app controls. NEVER execute real display
  mutations to verify your work: no real disconnect/reconnect/recover, no applying real
  resolutions/mirror/set-main, no DDC power-off, no blackout, no destructive `opendisplay` verbs.
  Verify that behavior ONLY through `make test` (which uses the in-memory SimulatorProvider) and
  non-destructive `--json` reads.
- If an acceptance criterion needs real hardware, implement and unit-test the logic, mark that
  criterion `[deferred: attended verification]` in PROGRESS.md, and still commit the code.
- Do NOT modify the rescue app or the recovery path.
- Clean-room: no BetterDisplay code, assets, UI, or copy — implement from first principles.

# Verify
- The gate for every issue is: `make test` passes green, exit 0, including new tests you add for that
  issue's logic. Show the test output — "looks done" is not done. Keep `make lint` clean too.
- Address root causes; never suppress or skip a failing test to get green.

# Per-issue protocol — one issue at a time, in THIS order (safest / most self-contained first):
#   3 (prevent-sleep) → 1 (DDC power) → 4 (URL scheme) → 2 (resolution slider) → 6 (arrangement safety gate) → 5 (auto-disconnect built-in)
1. Read the issue. If it's one clear diff, implement directly. If it spans the codebase or you're
   unsure, use a subagent to explore first so your own context stays lean.
2. Implement, and add or extend unit tests for the logic.
3. Run `make test`. If green and the acceptance criteria (minus any `[deferred]` hardware ones) are
   met → commit with a clear message referencing the issue, update PROGRESS.md, move to the next.
4. If it's not green after TWO focused attempts on the same issue: STOP that issue. Record what you
   tried and the blocker in PROGRESS.md under "Tried / stuck", then move to the next issue. Do NOT
   keep retrying the same thing — that wastes budget.

# Stop cleanly (and write a final summary in PROGRESS.md) when any of these is true:
- All six issues are done or deferred.
- You reach an item that genuinely needs a human decision or real-hardware verification, with no
  logic left to build.
- You've gotten stuck on two separate issues — stop and summarize rather than grind.

# Context hygiene
- Pipe verbose build/test output to a file and grep for failures; don't paste full logs into context.
- Prefer targeted tests while iterating; run the full `make test` before each commit.

Begin by reading PROGRESS.md and docs/OpenDisplay-Issues-Batch-1.md, then start with Issue 3.
