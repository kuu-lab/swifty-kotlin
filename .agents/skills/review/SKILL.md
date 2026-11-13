---
name: review
description: >-
  Review the current branch diff — or an explicit target (PR number, branch, path, or rev range) — for correctness bugs (plus reuse/simplification/efficiency cleanups) at an effort level: low|medium|high|xhigh|max (default high). Flags: --fix applies findings to the working tree, --comment posts them as inline GitHub PR comments, --max-findings <n>|all caps the report. Ported from Claude Code's /code-review.
argument-hint: "[low|medium|high|xhigh|max] [target] [--fix] [--comment] [--max-findings <n>]"
subagent: true
---

# /review — code review

Invocation arguments (raw, may be empty): `$ARGUMENTS`

You are running a code review. Work through these steps in order: parse the arguments, resolve the review scope, run exactly ONE level pipeline, then apply the flags and emit the output contract.

## Step 1 — Parse the arguments

Scan the raw arguments for flags (they may appear anywhere):

- `--fix` — after reporting, apply the findings to the working tree (see Step 4)
- `--comment` — post the findings to the GitHub pull request as review comments (see Step 4)
- `--max-findings <n>` / `--max-findings=<n>` / `--max-findings all` — override the level's findings cap (`all` removes the cap)

From the remaining tokens: if the first one is exactly `low`, `medium`, `high`, `xhigh`, or `max`, that is the LEVEL. Otherwise LEVEL = `high`. Everything left over is the TARGET — a PR number (`1234`, `#1234`, or a github.com PR URL), a branch name, a file/dir path, or a rev range (`HEAD~15..HEAD`, `abc123^..abc123`, `main...feature`). TARGET may be empty.

`ultra` is not supported — it was a Claude-cloud-only review with no equivalent here. If requested, run `max` and say so in one line.

## Step 2 — Resolve the review scope

- **No TARGET**: run `git diff @{upstream}...HEAD` (fallbacks: `git diff main...HEAD`, then `git diff HEAD~1` when there is no upstream). Also run `git diff HEAD` and include uncommitted working-tree changes in scope — the review often runs before the commit. If the range diff is empty, the working-tree diff alone is the scope.
- **PR number / URL**: `gh pr view <n>` for title/body/context and `gh pr diff <n>` for the diff. Do NOT check out the PR branch.
- **Rev range** (`A..B`, `A...B`, `hash^..hash`): `git diff <range>`.
- **Branch name**: `git diff <default-branch>...<branch>`; detect the default branch via `git symbolic-ref refs/remotes/origin/HEAD` or `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`.
- **Path**: scope the default diff to it — `git diff @{upstream}...HEAD -- <path>` plus `git diff HEAD -- <path>`; if both are empty, review the file's current contents for correctness bugs instead.

Treat the resolved diff as the review scope.

## Step 3 — Run the level pipeline

Execute exactly ONE of the five pipelines below, matching LEVEL. Each pipeline's text is the complete instruction set for that level — follow it exactly. Where a pipeline says "Grep"/"Read"/"the Agent tool", use the `grep`/`read`/`run_subagent` tools; where it says to run git commands, use `exec`.

Note: subagents cannot spawn nested subagents by default, so `run_subagent` is unavailable inside this review. Wherever a pipeline mentions the Agent tool, do not error — perform each angle and each verification yourself, sequentially, in this context.

---

## LEVEL low — `1 diff pass → no verify → ≤4 findings`

### Turn 1 — read

One tool call: read the unified diff resolved in Step 2. Skip test/fixture hunks (`test/`, `spec/`, `__tests__/`, `*_test.*`, `*.test.*`, `fixtures/`, `testdata/`) — test-file changes are not reviewed at this level. No subagents, no full-file reads.

### Turn 2 — findings

Flag runtime-correctness bugs visible from the hunk alone: inverted/wrong condition, off-by-one, null/undefined deref where adjacent lines show the value can be absent, removed guard, falsy-zero check, missing `await`, wrong-variable copy-paste, error swallowed in a catch that should propagate. Also flag — still from the hunk alone — new code that duplicates an existing helper visible in the diff context, and dead code the diff leaves behind.

Do **not** flag style, naming, perf, missing tests, or anything outside the hunk.

Output at most **4 findings** (or the `--max-findings` cap if it is lower), most-severe first, one line each: `path/to/file.ext:123 — what's wrong and the concrete failure`. If nothing qualifies, output exactly `(none)`.

---

## LEVEL medium — `single careful diff pass → ≤15 findings`

You are reviewing a pull request for real bugs.

Review the diff as a careful senior engineer would: read every hunk, open the surrounding files for context as needed (`read`, `grep`, `git log`/`git blame`/`git show` via `exec`), and hunt for correctness issues — wrong or inverted conditions, off-by-one, null/undefined dereference, missing `await`, dropped error handling, removed guards or validations, broken callers of changed functions, races. Prefer real failure modes over style; every finding needs a concrete scenario in which the code misbehaves.

When you are done, produce at most **15 findings** (or the `--max-findings` cap if set) as a JSON array per the Output contract below, with `file`, `line`, `summary`, `failure_scenario`, and `category` filled per finding. Quality over quantity: include everything you genuinely believe is a real issue, and nothing you don't. After the JSON block, restate the findings one line each — `file:line — summary` — so they stay visible.

---

## LEVEL high — `8 inline angles → dedup (no verify) → ≤10 findings`

You are reviewing for **recall** at high effort: catch every real bug a careful reviewer would catch in one sitting. At this level, catching real bugs matters more than avoiding false positives. Err on the side of surfacing.

### Phase 1 — Find candidates (3 correctness angles + 3 cleanup angles + 1 altitude angle + 1 conventions angle, up to 6 each)

Run **8 independent finder angles** in sequence yourself, in THIS context — do NOT spawn subagents for them. Each surfaces **up to 6 candidate findings** with `file`, `line`, a one-line `summary`, and a concrete `failure_scenario`.

### Angle A — line-by-line diff scan

Read every hunk in the diff, line by line. Then `read` the enclosing function for each hunk — bugs in unchanged lines of a touched function are in scope (the change re-exposes or fails to fix them). For every line ask: what input, state, timing, or platform makes this line wrong? Look for inverted/wrong conditions, off-by-one, null/undefined deref, missing `await`, falsy-zero checks, wrong-variable copy-paste, error swallowed in catch, unescaped regex metachars.

### Angle B — removed-behavior auditor

For every line the diff DELETES or replaces, name the invariant or behavior it enforced, then search the new code for where that invariant is re-established. If you can't find it, that's a candidate: a removed guard, a dropped error path, a narrowed validation, a deleted test that was covering a real case.

### Angle C — cross-file tracer

For each function the diff changes, find its callers (`grep` for the symbol) and check whether the change breaks any call site: a new precondition, a changed return shape, a new exception, a timing/ordering dependency. Also check callees: does a parallel change in the same diff make a call unsafe?

### Reuse

The angles above hunt for bugs; this one and the next two hunt for cleanup in the changed code. Flag new code that re-implements something the codebase already has — `grep` shared/utility modules and files adjacent to the change, and name the existing helper to call instead.

### Simplification

Flag unnecessary complexity the diff adds: redundant or derivable state, copy-paste with slight variation, deep nesting, dead code left behind. Name the simpler form that does the same job.

### Efficiency

Flag wasted work the diff introduces: redundant computation or repeated I/O, independent operations run sequentially, blocking work added to startup or hot paths. Also flag long-lived objects built from closures or captured environments — they keep the entire enclosing scope alive for the object's lifetime (a memory leak when that scope holds large values); prefer a class/struct that copies only the fields it needs. Name the cheaper alternative.

### Altitude

Check that each change fixes the root cause at the right depth rather than patching a symptom with a fragile bandaid. Special cases layered on shared infrastructure are a sign the fix isn't deep enough — prefer the simpler, more general change to the underlying mechanism over adding special cases, and name that change.

### Conventions (rules files)

Find the rule files that govern the changed code: user-level rules (`~/.config/devin/AGENTS.md`, `~/.claude/CLAUDE.md`, `~/.devin/rules/*.md`, `~/.devin/global_rules.md`), the repo-root rule files (`AGENTS.md`, `AGENTS.local.md`, `AGENT.md`, `CLAUDE.md`, `.devin/rules/*.md`, `.devin/global_rules.md`, `.windsurf/rules/*.md`), plus any `AGENTS.md` / `CLAUDE.md` / rules file in a directory that is an ancestor of a changed file (a directory's rules file only applies to files at or below it). `read` each one that exists, then check the diff for clear violations of the rules they state.

Only flag a violation when you can quote the exact rule and the exact line that breaks it — no style preferences, no vague "spirit of the doc" inferences. In the finding, name the rules-file path and quote the rule so the report can cite it. If no rules file applies, return nothing for this angle.

Cleanup, altitude, and conventions candidates use the same `file`/`line`/`summary` shape; in `failure_scenario`, state the concrete cost (what is duplicated, wasted, harder to maintain, or which rule is broken) instead of a crash. Correctness bugs always outrank cleanup, altitude, and conventions findings when the output cap forces a cut.

Pass every candidate with a nameable failure scenario through — finders that silently drop half-believed candidates are the dominant cause of misses.

### Phase 2 — Dedup only (no verify)

Pool all candidates. Dedup near-duplicates only (same defect, same location, same reason → keep one). Do NOT run verifiers; do NOT re-judge. Sort by severity.

### Output

Target **at least 5 findings**. If fewer genuine findings exist, emit what you have — do not invent to hit the floor.

Return findings as a JSON array of at most **10 objects** (or the `--max-findings` cap if set), per the Output contract below. Ranked most-severe first. If more than the cap survive, keep the most severe. If nothing survives, return `[]`.

---

## LEVEL xhigh — `10 inline angles → dedup (no verify) → sweep → ≤15 findings`

You are reviewing for **recall** at extra-high effort: catch every real bug. At this level, catching real bugs matters more than avoiding false positives — a missed bug ships. Err on the side of surfacing.

### Phase 1 — Find candidates (5 correctness angles + 3 cleanup angles + 1 altitude angle + 1 conventions angle, up to 8 each)

Run **10 independent finder angles** in sequence yourself, in THIS context — do NOT spawn subagents for them. Each surfaces **up to 8 candidate findings**. Do NOT let one angle's conclusions suppress another's — if two angles flag the same line for different reasons, record both.

### Angle A — line-by-line diff scan

Read every hunk in the diff, line by line. Then `read` the enclosing function for each hunk — bugs in unchanged lines of a touched function are in scope (the change re-exposes or fails to fix them). For every line ask: what input, state, timing, or platform makes this line wrong? Look for inverted/wrong conditions, off-by-one, null/undefined deref, missing `await`, falsy-zero checks, wrong-variable copy-paste, error swallowed in catch, unescaped regex metachars.

### Angle B — removed-behavior auditor

For every line the diff DELETES or replaces, name the invariant or behavior it enforced, then search the new code for where that invariant is re-established. If you can't find it, that's a candidate: a removed guard, a dropped error path, a narrowed validation, a deleted test that was covering a real case.

### Angle C — cross-file tracer

For each function the diff changes, find its callers (`grep` for the symbol) and check whether the change breaks any call site: a new precondition, a changed return shape, a new exception, a timing/ordering dependency. Also check callees: does a parallel change in the same diff make a call unsafe?

### Angle D — language-pitfall specialist

Scan for the classic pitfalls of the diff's language/framework — for example: JS falsy-zero, `==` coercion, closure-captured loop var; Python mutable default args, late-binding closures; Go nil-map write, range-var capture; SQL injection; timezone/DST drift; float equality. Flag any instance the diff introduces.

### Angle E — wrapper/proxy correctness

When the diff adds or modifies a type that wraps another (cache, proxy, decorator, adapter): check that every method routes to the wrapped instance and not back through a registry/session/global — e.g. a caching provider holding a `delegate` field that resolves IDs via `session.get(...)` instead of `delegate.get(...)` will re-enter the cache or recurse. Also check that the wrapper forwards all the methods the callers actually use.

### Reuse

The angles above hunt for bugs; this one and the next two hunt for cleanup in the changed code. Flag new code that re-implements something the codebase already has — `grep` shared/utility modules and files adjacent to the change, and name the existing helper to call instead.

### Simplification

Flag unnecessary complexity the diff adds: redundant or derivable state, copy-paste with slight variation, deep nesting, dead code left behind. Name the simpler form that does the same job.

### Efficiency

Flag wasted work the diff introduces: redundant computation or repeated I/O, independent operations run sequentially, blocking work added to startup or hot paths. Also flag long-lived objects built from closures or captured environments — they keep the entire enclosing scope alive for the object's lifetime (a memory leak when that scope holds large values); prefer a class/struct that copies only the fields it needs. Name the cheaper alternative.

### Altitude

Check that each change fixes the root cause at the right depth rather than patching a symptom with a fragile bandaid. Special cases layered on shared infrastructure are a sign the fix isn't deep enough — prefer the simpler, more general change to the underlying mechanism over adding special cases, and name that change.

### Conventions (rules files)

Find the rule files that govern the changed code: user-level rules (`~/.config/devin/AGENTS.md`, `~/.claude/CLAUDE.md`, `~/.devin/rules/*.md`, `~/.devin/global_rules.md`), the repo-root rule files (`AGENTS.md`, `AGENTS.local.md`, `AGENT.md`, `CLAUDE.md`, `.devin/rules/*.md`, `.devin/global_rules.md`, `.windsurf/rules/*.md`), plus any `AGENTS.md` / `CLAUDE.md` / rules file in a directory that is an ancestor of a changed file (a directory's rules file only applies to files at or below it). `read` each one that exists, then check the diff for clear violations of the rules they state.

Only flag a violation when you can quote the exact rule and the exact line that breaks it — no style preferences, no vague "spirit of the doc" inferences. In the finding, name the rules-file path and quote the rule so the report can cite it. If no rules file applies, return nothing for this angle.

Cleanup, altitude, and conventions candidates use the same `file`/`line`/`summary` shape; in `failure_scenario`, state the concrete cost (what is duplicated, wasted, harder to maintain, or which rule is broken) instead of a crash. Correctness bugs always outrank cleanup, altitude, and conventions findings when the output cap forces a cut.

### Phase 2 — Dedup only (no verify)

Pool all candidates. Dedup near-duplicates only (same defect, same location, same reason → keep one). Do NOT run verifiers; do NOT re-judge. Sort by severity. Do NOT drop on uncertainty.

### Phase 3 — Sweep for gaps

Take one more pass (same context — no subagent) as a fresh reviewer who has the deduplicated list. Re-read the diff and enclosing functions looking ONLY for defects not already listed. Do not re-derive or re-confirm anything already there — the job is gaps. Focus on what the first pass tends to miss: moved/extracted code that dropped a guard or anchor; second-tier footguns (dataclass default evaluated once, `hash()` non-determinism, lock-scope shrink, predicate methods with side effects); setup/teardown asymmetry in tests; config defaults flipped.

Surface **up to 8 additional candidates**, each naming a defect not already on the list. If nothing new, return nothing from this phase — do not pad.

### Output

Target **at least 7 findings**. If fewer genuine findings exist, emit what you have — do not invent to hit the floor.

Return findings as a JSON array of at most **15 objects** (or the `--max-findings` cap if set), per the Output contract below. Ranked most-severe first. If more than the cap survive, keep the most severe. If nothing survives, return `[]`.

---

## LEVEL max — `10 angles → 1-vote verify → sweep → ≤15 findings`

You are reviewing for **recall** at maximum effort: catch every real bug. At this level, catching real bugs matters more than avoiding false positives — a missed bug ships. Err on the side of surfacing.

### Phase 1 — Find candidates (5 correctness angles + 3 cleanup angles + 1 altitude angle + 1 conventions angle, up to 8 each)

Run **10 independent finder angles** via `run_subagent` if available, each surfacing **up to 8 candidate findings**. Do NOT let one angle's conclusions suppress another's — if two angles flag the same line for different reasons, record both. If `run_subagent` is not available in your current tool set, do not error — perform each angle (and each verification) yourself, sequentially, in this context.

### Angle A — line-by-line diff scan

Read every hunk in the diff, line by line. Then `read` the enclosing function for each hunk — bugs in unchanged lines of a touched function are in scope (the change re-exposes or fails to fix them). For every line ask: what input, state, timing, or platform makes this line wrong? Look for inverted/wrong conditions, off-by-one, null/undefined deref, missing `await`, falsy-zero checks, wrong-variable copy-paste, error swallowed in catch, unescaped regex metachars.

### Angle B — removed-behavior auditor

For every line the diff DELETES or replaces, name the invariant or behavior it enforced, then search the new code for where that invariant is re-established. If you can't find it, that's a candidate: a removed guard, a dropped error path, a narrowed validation, a deleted test that was covering a real case.

### Angle C — cross-file tracer

For each function the diff changes, find its callers (`grep` for the symbol) and check whether the change breaks any call site: a new precondition, a changed return shape, a new exception, a timing/ordering dependency. Also check callees: does a parallel change in the same diff make a call unsafe?

### Angle D — language-pitfall specialist

Scan for the classic pitfalls of the diff's language/framework — for example: JS falsy-zero, `==` coercion, closure-captured loop var; Python mutable default args, late-binding closures; Go nil-map write, range-var capture; SQL injection; timezone/DST drift; float equality. Flag any instance the diff introduces.

### Angle E — wrapper/proxy correctness

When the diff adds or modifies a type that wraps another (cache, proxy, decorator, adapter): check that every method routes to the wrapped instance and not back through a registry/session/global — e.g. a caching provider holding a `delegate` field that resolves IDs via `session.get(...)` instead of `delegate.get(...)` will re-enter the cache or recurse. Also check that the wrapper forwards all the methods the callers actually use.

### Reuse

The angles above hunt for bugs; this one and the next two hunt for cleanup in the changed code. Flag new code that re-implements something the codebase already has — `grep` shared/utility modules and files adjacent to the change, and name the existing helper to call instead.

### Simplification

Flag unnecessary complexity the diff adds: redundant or derivable state, copy-paste with slight variation, deep nesting, dead code left behind. Name the simpler form that does the same job.

### Efficiency

Flag wasted work the diff introduces: redundant computation or repeated I/O, independent operations run sequentially, blocking work added to startup or hot paths. Also flag long-lived objects built from closures or captured environments — they keep the entire enclosing scope alive for the object's lifetime (a memory leak when that scope holds large values); prefer a class/struct that copies only the fields it needs. Name the cheaper alternative.

### Altitude

Check that each change fixes the root cause at the right depth rather than patching a symptom with a fragile bandaid. Special cases layered on shared infrastructure are a sign the fix isn't deep enough — prefer the simpler, more general change to the underlying mechanism over adding special cases, and name that change.

### Conventions (rules files)

Find the rule files that govern the changed code: user-level rules (`~/.config/devin/AGENTS.md`, `~/.claude/CLAUDE.md`, `~/.devin/rules/*.md`, `~/.devin/global_rules.md`), the repo-root rule files (`AGENTS.md`, `AGENTS.local.md`, `AGENT.md`, `CLAUDE.md`, `.devin/rules/*.md`, `.devin/global_rules.md`, `.windsurf/rules/*.md`), plus any `AGENTS.md` / `CLAUDE.md` / rules file in a directory that is an ancestor of a changed file (a directory's rules file only applies to files at or below it). `read` each one that exists, then check the diff for clear violations of the rules they state.

Only flag a violation when you can quote the exact rule and the exact line that breaks it — no style preferences, no vague "spirit of the doc" inferences. In the finding, name the rules-file path and quote the rule so the report can cite it. If no rules file applies, return nothing for this angle.

Cleanup, altitude, and conventions candidates use the same `file`/`line`/`summary` shape; in `failure_scenario`, state the concrete cost (what is duplicated, wasted, harder to maintain, or which rule is broken) instead of a crash. Correctness bugs always outrank cleanup, altitude, and conventions findings when the output cap forces a cut.

### Phase 2 — Verify (1-vote, 3-state)

Dedup candidates that point at the same line/mechanism, keeping the one with the most concrete failure scenario. For each remaining candidate, run **one verifier** (yourself, sequentially, if `run_subagent` is unavailable): give it the diff, the relevant file(s), and the candidate, and return exactly one of:

- **CONFIRMED** — can name the inputs/state that trigger it and the wrong output or crash. Quote the line.
- **PLAUSIBLE** — mechanism is real, trigger is uncertain (timing, env, config). State what would confirm it.
- **REFUTED** — factually wrong (code doesn't say that) or guarded elsewhere. Quote the line that proves it.

Keep candidates where the vote is CONFIRMED or PLAUSIBLE. Set each kept finding's `verdict` field accordingly.

This is recall mode — a single non-REFUTED vote carries the finding. Do NOT drop on uncertainty.

### Phase 3 — Sweep for gaps

Run **one more finder** as a fresh reviewer who has the verified list. Re-read the diff and enclosing functions looking ONLY for defects not already listed. Do not re-derive or re-confirm anything already there — the job is gaps. Focus on what the first pass tends to miss: moved/extracted code that dropped a guard or anchor; second-tier footguns (dataclass default evaluated once, `hash()` non-determinism, lock-scope shrink, predicate methods with side effects); setup/teardown asymmetry in tests; config defaults flipped.

Surface **up to 8 additional candidates**, each naming a defect not already on the list. If nothing new, return an empty sweep — do not pad.

### Output

Return findings as a JSON array of at most **15 objects** (or the `--max-findings` cap if set), per the Output contract below. Ranked most-severe first. If more than the cap survive, keep the most severe. If nothing survives verification, return `[]`.

---

## Step 4 — Apply flags

### `--fix`

After producing the findings report, apply them to the working tree with the `edit` tool. Apply only findings you are confident are real; skip uncertain or refuted ones. For each finding record an `outcome`: `fixed`, `skipped`, or `no_change_needed`. Then re-emit the JSON findings array with the `outcome` field set on each finding, followed by a one-line summary of what changed.

### `--comment`

Post the findings to the GitHub pull request as review comments using `gh` (requires the TARGET or current branch to resolve to a PR — `gh pr view` with no args resolves the current branch's PR; if no PR exists or `gh` is unavailable, print the findings instead and say why). Resolve the repo with `gh repo view --json nameWithOwner -q .nameWithOwner` and the PR number with `gh pr view <n> --json number -q .number` (or the explicit TARGET).

For each finding whose `line` falls inside the PR diff, post an inline comment:

```bash
COMMIT=$(gh pr view <n> --json headRefOid -q .headRefOid)
gh api repos/{owner}/{repo}/pulls/<n>/comments \
  -f commit_id="$COMMIT" -f path="<file>" -F line=<line> -f side=RIGHT \
  -f body="<summary>\n\n<failure_scenario>"
```

For findings whose line is not in the diff (or if inline posting fails), collect them into a single `gh pr comment <n> --body "<full findings report>"`. Finish with a one-line count of comments posted.

### `--max-findings`

Already applied as the cap inside whichever level pipeline ran.

## Output contract

Levels `medium`, `high`, `xhigh`, and `max` report findings as a JSON array (level `low` uses its own one-line format defined above). Emit the array as a fenced `json` code block in your final reply, followed by the restated one-line list (`file:line — summary`) so findings stay visible.

```json
[
  {
    "file": "path/to/file.ext",
    "line": 123,
    "summary": "one-sentence statement of the bug",
    "failure_scenario": "concrete inputs/state → wrong output/crash",
    "category": "correctness",
    "verdict": "CONFIRMED",
    "outcome": "fixed"
  }
]
```

- `file`, `summary`, `failure_scenario` are required per finding; `line` is the 1-indexed anchor line.
- `category` — short kebab-case slug (`correctness`, `simplification`, `efficiency`, `conventions`, `test-coverage`, ...). Omit for level `low`.
- `verdict` — `CONFIRMED` or `PLAUSIBLE`; set only when the level ran a verify pass (max).
- `outcome` — `fixed` / `skipped` / `no_change_needed`; set only when re-reporting after `--fix`.
- Ranked most-severe first. Return `[]` when nothing survives.
