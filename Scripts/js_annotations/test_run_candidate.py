#!/usr/bin/env python3
"""Regression tests for the JS-specific candidate-only runner."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT_DIR = Path(__file__).resolve().parent
RUNNER = SCRIPT_DIR / "run_candidate.py"
FAKE_COMPILE_CODE = "KSWIFTK-TEST-COMPILE"
FAKE_DIAGNOSTIC_MAP = {"schemaVersion": 1, "codes": {FAKE_COMPILE_CODE: "TEST_FAILURE"}}


FAKE_COMPILER = r'''#!/usr/bin/env python3
import json
from pathlib import Path
import sys
import time

args = sys.argv[1:]
source = Path(next(arg for arg in args if arg.endswith(".kt")))
mode = source.read_text(encoding="utf-8").split("MODE:", 1)[1].splitlines()[0].strip()
if mode == "compile-timeout":
    time.sleep(2)
    raise SystemExit(0)
if mode in {"compile-failure", "unknown-diagnostic"}:
    code = "KSWIFTK-TEST-COMPILE" if mode == "compile-failure" else "KSWIFTK-UNMAPPED"
    json.dump({"version": 1, "diagnostics": [{"code": code, "severityLabel": "error"}]}, sys.stderr)
    sys.stderr.write("\n")
    raise SystemExit(1)

output = Path(args[args.index("-o") + 1])
if mode == "stderr-mismatch":
    program = "#!/usr/bin/env python3\nimport sys\nsys.stderr.write('unexpected\\n')\n"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(program, encoding="utf-8")
    output.chmod(0o755)
    raise SystemExit(0)
if mode == "runtime-timeout":
    program = "#!/usr/bin/env python3\nimport time\ntime.sleep(2)\n"
elif mode == "runtime-failure":
    program = "#!/usr/bin/env python3\nimport sys\nsys.stderr.write('runtime failed\\n')\nraise SystemExit(9)\n"
else:
    stdout = "actual\n" if mode == "output-mismatch" else "ok\n"
    program = "#!/usr/bin/env python3\nimport sys\nsys.stdout.write(" + repr(stdout) + ")\n"
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(program, encoding="utf-8")
output.chmod(0o755)
'''


class CandidateRunnerRegressionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="js-annotations-runner-")
        self.root = Path(self.temp.name)
        self.fixture_root = self.root / "fixtures"
        self.fixture_root.mkdir()
        self.artifact_root = self.root / "artifacts"
        self.compiler = self.root / "fake_kswiftc"
        self.compiler.write_text(FAKE_COMPILER, encoding="utf-8")
        self.compiler.chmod(0o755)
        self.stdlib = self.root / "stdlib.kklib"
        self.stdlib.mkdir()
        (self.stdlib / "manifest.json").write_text("{}\n", encoding="utf-8")
        self.diagnostic_map = self.root / "diagnostic_map.json"
        self.diagnostic_map.write_text(json.dumps(FAKE_DIAGNOSTIC_MAP), encoding="utf-8")
        self.extra_env: dict[str, str] = {}

    def tearDown(self) -> None:
        self.temp.cleanup()

    def write_case(
        self,
        mode: str,
        *,
        expected_stdout: str = "ok\n",
        expected_exit: int = 0,
        expected_diagnostics: list[dict[str, str]] | None = None,
        include_run: bool = True,
        include_reference_run: bool = False,
        include_compile: bool = True,
    ) -> Path:
        source = self.fixture_root / "case.kt"
        source.write_text(f"// minimal runner fixture\n// MODE:{mode}\n", encoding="utf-8")
        case: dict[str, object] = {
            "id": "runner_regression",
            "source": source.name,
            "sourceSha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "lanes": ["native-compat"],
            "nativeContract": {"status": "required-by-followup-not-yet-implemented"},
        }
        contract = case["nativeContract"]
        assert isinstance(contract, dict)
        if include_compile:
            contract["compile"] = {
                "exitCode": expected_exit,
                "diagnostics": expected_diagnostics if expected_diagnostics is not None else [],
            }
        if include_run:
            contract["run"] = {"exitCode": 0, "stdout": expected_stdout, "stderr": ""}
        if include_reference_run:
            case["reference"] = {"run": {"exitCode": 0, "stdout": expected_stdout, "stderr": ""}}
        expectations = self.fixture_root / "expectations.json"
        expectations.write_text(
            json.dumps({"schemaVersion": 1, "cases": [case]}), encoding="utf-8"
        )
        return expectations

    def run_candidate(self, expectations: Path, *, timeout: str = "0.5") -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env["PATH"] = f"{self.root}{os.pathsep}{env.get('PATH', '')}"
        env.update(self.extra_env)
        return subprocess.run(
            [
                sys.executable,
                str(RUNNER),
                "--kswiftc",
                str(self.compiler),
                "--expectations",
                str(expectations),
                "--diagnostic-map",
                str(self.diagnostic_map),
                "--stdlib-library",
                str(self.stdlib),
                "--artifact-root",
                str(self.artifact_root),
                "--compile-timeout",
                timeout,
                "--run-timeout",
                timeout,
            ],
            cwd=SCRIPT_DIR.parents[1],
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

    def latest_run(self) -> Path:
        runs = sorted(self.artifact_root.iterdir())
        self.assertTrue(runs, "runner did not create an artifact run")
        return runs[-1]

    def read_summary(self) -> dict[str, object]:
        return json.loads((self.latest_run() / "summary.json").read_text(encoding="utf-8"))

    def test_success_is_candidate_only_and_saves_lane_and_output(self) -> None:
        marker = self.root / "jvm-called"
        for tool in ("java", "kotlinc"):
            trap = self.root / tool
            trap.write_text(
                "#!/usr/bin/env python3\n"
                "from pathlib import Path\n"
                "import os\n"
                "Path(os.environ['JVM_MARKER_FILE']).write_text('called')\n"
                "raise SystemExit(99)\n",
                encoding="utf-8",
            )
            trap.chmod(0o755)
        self.extra_env["JVM_MARKER_FILE"] = str(marker)
        expectations = self.write_case("success")
        result = self.run_candidate(expectations)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        summary = self.read_summary()
        self.assertFalse(summary["usedJvmReference"])
        case_dir = self.latest_run() / "cases/runner_regression"
        self.assertEqual((case_dir / "run.stdout").read_bytes(), b"ok\n")
        self.assertIn("lane=native-compat", result.stdout)
        self.assertFalse(marker.exists())

    def test_output_mismatch_is_nonzero_and_saved(self) -> None:
        expectations = self.write_case("output-mismatch", expected_stdout="expected\n")
        result = self.run_candidate(expectations)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("run_stdout_mismatch", result.stdout)
        case = self.read_summary()["cases"][0]
        self.assertIn("run_stdout_mismatch", case["failureReasons"])
        self.assertEqual(
            (self.latest_run() / "cases/runner_regression/run.stdout").read_bytes(),
            b"actual\n",
        )

    def test_stderr_mismatch_is_nonzero(self) -> None:
        expectations = self.write_case("stderr-mismatch")
        result = self.run_candidate(expectations)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("run_stderr_mismatch", result.stdout)

    def test_unexpected_compile_failure_is_nonzero(self) -> None:
        expectations = self.write_case("compile-failure")
        result = self.run_candidate(expectations)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("compile_exit_mismatch", result.stdout)

    def test_expected_compile_failure_is_compared(self) -> None:
        expectations = self.write_case(
            "compile-failure",
            expected_exit=1,
            expected_diagnostics=[{"severity": "error", "kind": "TEST_FAILURE"}],
            include_run=False,
        )
        result = self.run_candidate(expectations)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        case = self.read_summary()["cases"][0]
        self.assertEqual(case["status"], "pass")
        self.assertEqual(case["run"]["reason"], "expected-compile-failure")

    def test_unknown_diagnostic_code_is_nonzero(self) -> None:
        expectations = self.write_case("unknown-diagnostic", expected_exit=1, include_run=False)
        result = self.run_candidate(expectations)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("unknown_diagnostic_code:KSWIFTK-UNMAPPED", result.stdout)

    def test_runtime_failure_is_nonzero(self) -> None:
        expectations = self.write_case("runtime-failure")
        result = self.run_candidate(expectations)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("run_exit_code_mismatch", result.stdout)
        self.assertEqual(
            (self.latest_run() / "cases/runner_regression/run.stderr").read_bytes(),
            b"runtime failed\n",
        )

    def test_compile_timeout_is_nonzero(self) -> None:
        expectations = self.write_case("compile-timeout")
        result = self.run_candidate(expectations, timeout="0.1")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("compile_timeout", result.stdout)

    def test_run_timeout_is_nonzero(self) -> None:
        expectations = self.write_case("runtime-timeout")
        result = self.run_candidate(expectations, timeout="0.1")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("run_timeout", result.stdout)

    def test_missing_expectation_is_nonzero_not_skipped(self) -> None:
        expectations = self.write_case("success", include_compile=False)
        result = self.run_candidate(expectations)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("missing_compile_expectation", result.stdout)
        self.assertNotIn("SKIP", result.stdout)

    def test_missing_run_expectation_is_nonzero(self) -> None:
        expectations = self.write_case(
            "success", include_run=False, include_reference_run=True
        )
        result = self.run_candidate(expectations)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("missing_expected_run", result.stdout)


if __name__ == "__main__":
    unittest.main()
