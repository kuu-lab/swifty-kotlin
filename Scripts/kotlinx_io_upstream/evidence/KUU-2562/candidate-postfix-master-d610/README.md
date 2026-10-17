# Supplemental post-fix master matrix

This is a separate run against the fixed master candidate `d610e43f3275f9f5603a41543bd5b77ab7e067b0`. It supplements the issue-pinned `fd01a5e98145e8295e5b299b0a7190cc8d44e3a7` evidence and does not replace it.

- Six lanes: source, stdlib-library, producer-consumer × O0/O2.
- Each lane: 20/20 JVM-origin assertions PASS; compile=0; run=0; contract probe=4/4 PASS.
- Producer-consumer test-library compile: 0 in both optimization lanes.
- Compiler SHA-256: `547284439d17ef2cb017e150af117b047605e50604ce96efdc3b546ab947122f`.
- Fresh stdlib KLIB manifest SHA-256: `2463b9b1962e1368448a57282e669ecd2d881ee918d9c9fe5e735bf3ccc47ee8`; tree SHA-256: `6a31d1a0b648769826ae9e1b233ed717619bc9782d59f82de07e8270e6767983` (1,859 files).
- Probe compares exception simple names after a typed `failure is T` assertion, allowing JVM/Native platform aliases while preserving the required exception type check.
- Exact aggregate SHA-256: see `matrix-summary-normalized.json.sha256`.
- Large generated executables and object files are intentionally omitted; commands, environment, source inputs, test results, and hashes are retained.
