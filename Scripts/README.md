# Scripts workflow

`Scripts/swift_test.sh` wraps `swift test` with parallel execution enabled by default.

- Tune workers: `SWIFT_TEST_WORKERS=4 bash Scripts/swift_test.sh`
- Tune build jobs: `SWIFT_TEST_BUILD_JOBS=4 bash Scripts/swift_test.sh`
- Disable parallel mode: `SWIFT_TEST_PARALLEL=0 bash Scripts/swift_test.sh`

When you are iterating on test failures after a successful build, you can also
reuse the existing build products:

```bash
bash Scripts/swift_test.sh --skip-build
```

## Runtime ABI link validation

Validate compiler runtime link names against `RuntimeABISpec`:

```bash
bash Scripts/validate_runtime_abi_links.sh
```

## Golden update workflow

1. Run golden tests without updating fixtures:

```bash
bash Scripts/swift_test.sh --filter Golden
```

2. Review differences:

```bash
git diff -- Tests/CompilerCoreTests/GoldenCases
```

3. If the parser/sema/lowering change is intentional, update fixtures:

```bash
UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden
```

4. Re-review fixture changes and ensure only intended files changed:

```bash
git status --short
git diff -- Tests/CompilerCoreTests/GoldenCases
```

5. Validate before commit:

```bash
bash Scripts/swift_test.sh
bash Scripts/diff_kotlinc.sh Scripts/diff_cases
```

### Golden stability (after harness / concurrency changes)

Golden tests run each case in a dedicated worker process so `swift test --parallel` can fan them out safely. To sanity-check flakiness after harness changes, run the filter twice (or more):

```bash
bash Scripts/swift_test.sh --filter Golden
bash Scripts/swift_test.sh --filter Golden
```

## kotlinc diff workflow

Run one case:

```bash
bash Scripts/diff_kotlinc.sh Scripts/diff_cases/hello.kt
```

Run all tracked regression cases:

```bash
bash Scripts/diff_kotlinc.sh Scripts/diff_cases
```

For coroutine/Flow cases, `diff_kotlinc.sh` can automatically download
`kotlinx-coroutines-core-jvm` when needed (if no `--kotlinc-classpath` is
set).  
You can control the cached path and version with:

```bash
export KOTLINC_COROUTINES_VERSION=1.10.2
export KOTLINC_DEP_DIR=/path/to/.runtime-build/deps
```

Emit a machine-readable report (TSV) for CI tooling:

```bash
bash Scripts/diff_kotlinc.sh --report /tmp/diff_report.tsv Scripts/diff_cases
```

Omit `PASS` lines in logs (CI uses `DIFF_LOG_PASS=0`):

```bash
DIFF_LOG_PASS=0 bash Scripts/diff_kotlinc.sh Scripts/diff_cases
```

You can control parallel execution:

```bash
# Enable/disable with environment variable
DIFF_PARALLEL=1 bash Scripts/diff_kotlinc.sh Scripts/diff_cases
DIFF_PARALLEL=0 bash Scripts/diff_kotlinc.sh Scripts/diff_cases

# Override workers explicitly
DIFF_WORKERS=4 bash Scripts/diff_kotlinc.sh Scripts/diff_cases

# Or via command line options
bash Scripts/diff_kotlinc.sh --parallel --jobs 4 Scripts/diff_cases
bash Scripts/diff_kotlinc.sh --no-parallel Scripts/diff_cases
```

`DIFF_PARALLEL`/`DIFF_WORKERS` parallelize within one machine. To split the case
set across several machines (CI shards the regression over 4 runners this way),
use interleaved sharding — case `i` runs only when `i % count == index`:

```bash
# 4 shards; each prints/reports only its ~1/4 of the cases.
DIFF_SHARD_INDEX=0 DIFF_SHARD_COUNT=4 bash Scripts/diff_kotlinc.sh Scripts/diff_cases
DIFF_SHARD_INDEX=1 DIFF_SHARD_COUNT=4 bash Scripts/diff_kotlinc.sh Scripts/diff_cases
# ...and shards 2, 3 on other machines. Combine with --jobs for per-machine parallelism.

# Equivalent flags
bash Scripts/diff_kotlinc.sh --shard-index 0 --shard-count 4 Scripts/diff_cases
```

Sharding and `DIFF_WORKERS` compose: a shard still runs its slice across the
configured workers. `DIFF_SHARD_COUNT=1` (the default) disables sharding.

Render a markdown summary from that report:

```bash
bash Scripts/diff_kotlinc_ci_summary.sh --report /tmp/diff_report.tsv --summary /tmp/step_summary.md
```
