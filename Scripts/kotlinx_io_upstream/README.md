# kotlinx-io upstream test matrix

This directory contains a strict paired-run harness for cases from the pinned
`kotlinx-io` 0.9.1 sources. It is separate from the stdlib API ledger and from
`Scripts/diff_kotlinc.sh`, whose cases are compiler-authored programs rather
than upstream test IDs.

## Runner contract

`run_matrix.py` takes a JSON manifest. Each `run` case has one reference and
candidate command, each as an argv array (no implicit shell). The command gets
`KIO_CASE_ID`, `KIO_UPSTREAM_ID`, `KIO_PLATFORM`, `KIO_SIDE`, `KIO_REPO_ROOT`,
and `KIO_ARTIFACT_DIR`. Arguments may use `{repo}`, `{source}`, `{case_id}`,
`{upstream_id}`, `{platform}`, `{side}`, and `{artifact_dir}` placeholders.

Each command writes exactly one JSON object to stdout. The harness requires
these fields and compares the full object:

```json
{
  "stdout": "program output",
  "exception_type": null,
  "bytes_consumed": 0,
  "buffer_state": null,
  "byte_buffer_state": null,
  "callbacks": null,
  "resource_lifecycle": null
}
```

Put compiler/test-runner diagnostics on stderr. A timeout is `HANG`; a nonzero
exit is `CRASH`; malformed protocol data is `ERROR`; unequal observations are
`DIFFERENCE`. Explicit `skip`, `unsupported`, and `unmapped` dispositions and
declared `expected_failure` results are retained as separate non-pass counts.
The command exits 0 only when every selected case is `PASS`, exits 2 when the
matrix is incomplete, and exits 1 for a test/protocol failure. Thus an empty
selection or a suite containing only skips cannot look green.

Each invocation writes `summary.json`, `summary.md`, one `cases/<id>/result.json`
per case, and the exact stdout/stderr of each side to a unique run directory
under `.artifacts/kotlinx_io_upstream/` by default. The summary records pinned
versions, host/runtime information, repository SHA/dirty state, and counts by
classification for CI artifact upload.

## Current scope and upstream coverage not included

This work adds the generic runner/classifier, a generated catalog-derived case
map, and its synthetic regression matrix. The checked-in map contains 684
test/sample function IDs from 61 upstream source files at the pinned
`0.9.1` commit. Each entry carries its source blob SHA, candidate suite names,
and any local test references suggested by the API crosswalk. Those local
references are explicitly unverified, and every case remains unmapped or
unsupported until a paired runner is configured.

The catalog does **not** count concrete executions: it does not expand
inherited abstract test suites, factory values, parameterized invocations, or
the assertions inside a test method. Seven source files have no catalogued
test/sample function and are retained as inventory-only helpers. Run
`import_inventory.py` to regenerate the map from the pinned catalog and
crosswalk; it preserves the source-set target label (for example, `js` and
`native-nonapple`), checks the expected upstream commit and, when supplied,
the lockfile SHA for the index. Only `common` and `jvm` rows are in this
macOS harness's prospective execution scope; other source sets remain
explicitly unsupported rather than being folded into `common`.

```sh
python3 Scripts/kotlinx_io_upstream/import_inventory.py \
  --test-index /path/to/io_api_inventory/upstream-tests-index.json \
  --api-inventory /path/to/io_api_inventory/api-inventory.tsv \
  --upstream-lock /path/to/io_api_inventory/upstream-lock.json \
  --output Scripts/kotlinx_io_upstream/coverage-map.seed.json
```

The map still does **not** execute any upstream tests, including
`core/common/test`, `core/jvm/test`, `core/native/test`, Apple-specific tests,
`bytestring/common/test`, `bytestring/jvm/test`, or their samples. No Native
reference adapter is configured here. The exact Kotlin 2.3.10 compiler and the
pinned kotlinx-io 0.9.1 JVM jars are not available in this worktree (the
installed compiler is 2.4.20), and the upstream Gradle test sources are absent;
therefore no real upstream reference/candidate case ran. The repository's existing
`Scripts/diff_cases/kotlinx_io_*` programs and Swift integration tests are
useful local coverage, but they do not yet provide a verified
upstream-assertion-to-local-test mapping.
[`coverage-map.seed.json`](coverage-map.seed.json) records all indexed IDs as
`unmapped` or `unsupported`, so none are included in a pass count.

The next step is to check out tag `0.9.1` with its Gradle test sources and
expand inherited suites, factories, parameter values, and sample invocations
into stable case IDs. Then add the JVM reference and KSwiftK candidate adapters
and move only runnable rows from `unmapped` to `run`. Until then, use explicit
`unmapped`/`unsupported`/`skip` dispositions; never count absent rows as passed.
