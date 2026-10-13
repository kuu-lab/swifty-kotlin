#!/usr/bin/env python3
"""Regression tests for the source/artifact O0/O2 matrix runner."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import run_matrix


SCRIPT_DIR = Path(__file__).resolve().parent
RUNNER = SCRIPT_DIR / "run_matrix.py"
WARNING_CODE = "KSWIFTK-TEST-WARNING"
ERROR_CODE = "KSWIFTK-TEST-ERROR"
DIAGNOSTIC_MAP = {
    "schemaVersion": 1,
    "codes": {WARNING_CODE: "TEST_WARNING", ERROR_CODE: "TEST_ERROR"},
}


FAKE_COMPILER = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
if "--stdlib-only" in args:
    output = Path(args[args.index("-o") + 1])
    output.mkdir(parents=True, exist_ok=False)
    (output / "manifest.json").write_text('{"fake":true}\n', encoding="utf-8")
    (output / "stdlib.bin").write_bytes(b"fresh-fake-stdlib")
    raise SystemExit(0)

source = Path(next(arg for arg in args if arg.endswith(".kt")))
stdout_by_case = json.loads(os.environ.get("FAKE_RUN_STDOUTS", "{}"))
stdlib_mode = "source-injection" if "--stdlib-from-source" in args else "stdlib-kklib"
optimization = next(arg[1:] for arg in args if arg in {"-O0", "-O2"})
slot = f"{stdlib_mode}:{optimization}"
diagnostics = json.loads(os.environ.get("FAKE_DIAGNOSTICS", "[]"))
if os.environ.get("FAKE_CORRUPT_DIAGNOSTIC_SLOT") == slot and diagnostics:
    diagnostics = diagnostics[:-1]
if diagnostics:
    json.dump({"version": 1, "diagnostics": diagnostics}, sys.stderr)
    sys.stderr.write("\n")

compile_exit = int(os.environ.get("FAKE_COMPILE_EXIT", "0"))
if compile_exit != 0:
    raise SystemExit(compile_exit)

stdout = stdout_by_case.get(source.stem, os.environ.get("FAKE_RUN_STDOUT", "ok\n"))
stderr = os.environ.get("FAKE_RUN_STDERR", "")
run_exit = int(os.environ.get("FAKE_RUN_EXIT", "0"))
if os.environ.get("FAKE_CORRUPT_OUTPUT_SLOT") == slot:
    stdout = os.environ.get("FAKE_CORRUPTED_STDOUT", "corrupted\n")
output = Path(args[args.index("-o") + 1])
output.parent.mkdir(parents=True, exist_ok=True)
program = (
    "#!/usr/bin/env python3\n"
    "import sys\n"
    f"sys.stdout.write({stdout!r})\n"
    f"sys.stderr.write({stderr!r})\n"
    f"raise SystemExit({run_exit})\n"
)
output.write_text(program, encoding="utf-8")
output.chmod(0o755)
'''


class MatrixRunnerRegressionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="js-annotations-matrix-")
        self.root = Path(self.temp.name)
        self.fixture_root = self.root / "fixtures"
        self.fixture_root.mkdir()
        self.artifact_root = self.root / "artifacts"
        self.compiler = self.root / "fake_kswiftc"
        self.compiler.write_text(FAKE_COMPILER, encoding="utf-8")
        self.compiler.chmod(0o755)
        self.swift = self.root / "swift"
        self.swift.write_text("#!/bin/sh\nprintf 'Swift version 6.3.0\\n'\n", encoding="utf-8")
        self.swift.chmod(0o755)
        self.diagnostic_map = self.root / "diagnostic_map.json"
        self.diagnostic_map.write_text(json.dumps(DIAGNOSTIC_MAP), encoding="utf-8")
        self.extra_env: dict[str, str] = {}

    def tearDown(self) -> None:
        self.temp.cleanup()

    def write_case(
        self,
        case_id: str = "matrix_regression",
        *,
        expected_stdout: str | None = "ok\n",
        compile_exit: int = 0,
        expected_diagnostics: list[dict[str, str]] | None = None,
    ) -> Path:
        source = self.fixture_root / f"{case_id}.kt"
        source.write_text("// deterministic matrix fixture\n", encoding="utf-8")
        compile_contract: dict[str, object] = {
            "exitCode": compile_exit,
            "diagnostics": expected_diagnostics or [],
        }
        native_contract: dict[str, object] = {"compile": compile_contract}
        if expected_stdout is not None:
            native_contract["run"] = {
                "exitCode": 0,
                "stdout": expected_stdout,
                "stderr": "",
            }
        case = {
            "id": case_id,
            "source": source.name,
            "sourceSha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "lanes": ["native-compat"],
            "provenance": {"capture": "fake-evidence.json", "pointer": f"/cases/{case_id}"},
            "nativeContract": native_contract,
        }
        expectations = self.fixture_root / "expectations.json"
        expectations.write_text(
            json.dumps({"schemaVersion": 1, "cases": [case]}), encoding="utf-8"
        )
        return expectations

    def run_matrix(
        self,
        expectations: Path | list[Path],
        *,
        run_stdout: str = "ok\n",
        compile_exit: int = 0,
        diagnostics: list[dict[str, str]] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env["PATH"] = f"{self.root}{os.pathsep}{env.get('PATH', '')}"
        env.update(
            {
                "FAKE_RUN_STDOUT": run_stdout,
                "FAKE_COMPILE_EXIT": str(compile_exit),
                "FAKE_DIAGNOSTICS": json.dumps(diagnostics or []),
            }
        )
        env.update(self.extra_env)
        expectation_paths = expectations if isinstance(expectations, list) else [expectations]
        command = [
                sys.executable,
                str(RUNNER),
                "--kswiftc",
                str(self.compiler),
                "--artifact-root",
                str(self.artifact_root),
                "--compile-timeout",
                "5",
                "--run-timeout",
                "5",
                "--stdlib-timeout",
                "5",
            ]
        for expectation in expectation_paths:
            command.extend(["--expectations", str(expectation)])
            command.extend(["--diagnostic-map", str(self.diagnostic_map)])
        return subprocess.run(
            command,
            cwd=SCRIPT_DIR.parents[1],
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

    def latest_run(self) -> Path:
        runs = sorted(self.artifact_root.iterdir())
        self.assertTrue(runs, "matrix runner did not create an artifact run")
        return runs[-1]

    def read_summary(self) -> dict[str, object]:
        return json.loads((self.latest_run() / "summary.json").read_text(encoding="utf-8"))

    def test_full_matrix_uses_one_fresh_artifact_and_records_identity(self) -> None:
        expectations = self.write_case()
        result = self.run_matrix(expectations)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        summary = self.read_summary()
        self.assertEqual(summary["status"], "pass")
        self.assertEqual(len(summary["matrix"]), 4)
        artifact = summary["artifact"]
        self.assertIsInstance(artifact, dict)
        self.assertEqual(
            artifact["builderCompilerSha256"], summary["identity"]["compiler"]["sha256"]
        )
        self.assertEqual(
            artifact["builderSourceTreeSha256"],
            summary["identity"]["compilerSourceTree"]["sha256"],
        )
        self.assertEqual(artifact["builderGitRevision"], summary["identity"]["gitRevision"])
        self.assertEqual(len(summary["cases"]), 4)
        self.assertEqual(len(summary["caseConsistency"]), 1)

        run_root = self.latest_run()
        evidence_path = self.root / "portable-evidence.json"
        run_matrix.write_portable_evidence(evidence_path, summary)
        evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
        self.assertEqual(evidence["runId"], summary["runId"])
        self.assertEqual(len(evidence["cases"]), 1)
        self.assertEqual(evidence["cases"][0]["id"], "matrix_regression")
        self.assertEqual(evidence["expectationInputs"][0]["path"], "<external>/expectations.json")
        self.assertEqual(
            evidence["diagnosticMapInputs"][0]["path"], "<external>/diagnostic_map.json"
        )
        self.assertEqual(
            evidence["cases"][0]["expectationSources"], ["<external>/expectations.json"]
        )
        self.assertEqual(
            (evidence_path.parent / evidence["artifactRunDirectory"]).resolve(), run_root.resolve()
        )

        artifact_path = (run_root / artifact["path"]).resolve()
        self.assertTrue((artifact_path / "manifest.json").is_file())
        self.assertEqual(artifact["sha256"], run_matrix.directory_digest(artifact_path)["sha256"])
        self.assertEqual(evidence["artifact"]["buildCommand"], artifact["buildCommand"])
        source_command = json.loads(
            (run_root / "cases/matrix_regression/source-injection-O0/compile.json").read_text()
        )["command"]
        artifact_command = json.loads(
            (run_root / "cases/matrix_regression/stdlib-kklib-O2/compile.json").read_text()
        )["command"]
        self.assertIn("--stdlib-from-source", source_command)
        self.assertIn("--stdlib-library", artifact_command)
        self.assertIn(str(artifact_path), artifact_command)
        self.assertNotIn("--stdlib-library", source_command)

    def test_output_change_in_one_mode_is_a_failure(self) -> None:
        expected = "ExportedBox:7:0\ndefault:41:1\ndefault:42:2\n"
        expectations = self.write_case("reflection", expected_stdout=expected)
        self.extra_env.update(
            {
                "FAKE_CORRUPT_OUTPUT_SLOT": "stdlib-kklib:O2",
                "FAKE_CORRUPTED_STDOUT": "ExportedBox:7:0\ndefault:41:1\ndefault:0:0\n",
            }
        )
        result = self.run_matrix(expectations, run_stdout=expected)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        case_result = json.loads(
            (
                self.latest_run()
                / "cases/reflection/stdlib-kklib-O2/result.json"
            ).read_text(encoding="utf-8")
        )
        self.assertIn("run_stdout_mismatch", case_result["failureReasons"])
        self.assertEqual(case_result["status"], "fail")

    def test_expected_negative_diagnostics_are_checked_in_all_modes(self) -> None:
        expected = [{"severity": "error", "kind": "TEST_ERROR"}]
        diagnostics = [{"code": ERROR_CODE, "severityLabel": "error"}]
        expectations = self.write_case(
            "negative_metadata", expected_stdout=None, compile_exit=1, expected_diagnostics=expected
        )
        result = self.run_matrix(expectations, compile_exit=1, diagnostics=diagnostics)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.read_summary()["counts"]["failed"], 0)

    def test_missing_marker_diagnostic_in_one_mode_is_a_failure(self) -> None:
        expected = [{"severity": "warning", "kind": "TEST_WARNING"}] * 3
        diagnostics = [{"code": WARNING_CODE, "severityLabel": "warning"}] * 3
        expectations = self.write_case(
            "marker_no_opt_in", expected_stdout="ok\n", expected_diagnostics=expected
        )
        self.extra_env["FAKE_CORRUPT_DIAGNOSTIC_SLOT"] = "stdlib-kklib:O2"
        result = self.run_matrix(expectations, diagnostics=diagnostics)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        case_result = json.loads(
            (
                self.latest_run()
                / "cases/marker_no_opt_in/stdlib-kklib-O2/result.json"
            ).read_text(encoding="utf-8")
        )
        self.assertIn("compile_diagnostics_mismatch", case_result["failureReasons"])

    def test_multiple_contract_sets_merge_duplicate_views_without_losing_sources(self) -> None:
        first_root = self.fixture_root / "annotations"
        second_root = self.fixture_root / "views"
        first_root.mkdir()
        second_root.mkdir()

        def make_case(root: Path, case_id: str, output: str) -> dict[str, object]:
            source = root / f"{case_id}.kt"
            source.write_text("// deterministic matrix fixture\n", encoding="utf-8")
            return {
                "id": case_id,
                "source": source.name,
                "sourceSha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                "lanes": ["native-compat"],
                "provenance": {"capture": "fake-evidence.json", "pointer": f"/cases/{case_id}"},
                "nativeContract": {
                    "compile": {"exitCode": 0, "diagnostics": []},
                    "run": {"exitCode": 0, "stdout": output, "stderr": ""},
                },
            }

        first_cases = [make_case(first_root, "alpha", "alpha\n"), make_case(first_root, "shared", "shared\n")]
        second_cases = [make_case(second_root, "shared", "shared\n"), make_case(second_root, "omega", "omega\n")]
        first_expectations = first_root / "expectations.json"
        second_expectations = second_root / "expectations.json"
        for path, cases in ((first_expectations, first_cases), (second_expectations, second_cases)):
            path.write_text(json.dumps({"schemaVersion": 1, "cases": cases}), encoding="utf-8")

        self.extra_env["FAKE_RUN_STDOUTS"] = json.dumps(
            {"alpha": "alpha\n", "shared": "shared\n", "omega": "omega\n"}
        )
        result = self.run_matrix([first_expectations, second_expectations])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        summary = self.read_summary()
        self.assertEqual(summary["counts"]["caseConsistency"], 3)
        self.assertEqual(summary["counts"]["caseRuns"], 12)
        self.assertEqual(len(summary["expectationInputs"]), 2)
        shared = next(case for case in summary["cases"] if case["id"] == "shared")
        self.assertEqual(len(shared["expectationSources"]), 2)

    def test_required_sentinels_pin_metadata_receiver_defaults_and_views(self) -> None:
        contract_pairs = tuple(
            (path.resolve(), mapping.resolve()) for path, mapping in run_matrix.DEFAULT_CONTRACT_PAIRS
        )
        document, _ = run_matrix.load_contract_sets(contract_pairs)
        self.assertEqual(run_matrix.validate_required_sentinels(document["cases"]), [])

        for case_id, mutation, expected_error in (
            (
                "marker_no_opt_in",
                lambda case: case["nativeContract"]["compile"].update(diagnostics=[]),
                "required_sentinel_diagnostics_changed:marker_no_opt_in",
            ),
            (
                "unbound_create_instance",
                lambda case: case["nativeContract"]["run"].update(stdout="wrong\n"),
                "required_sentinel_stdout_changed:unbound_create_instance",
            ),
            (
                "reflection",
                lambda case: case["nativeContract"]["run"].update(stdout="wrong\n"),
                "required_sentinel_stdout_changed:reflection",
            ),
            (
                "views_map",
                lambda case: case["nativeContract"]["run"].update(stdout="size only\n"),
                "required_sentinel_stdout_changed:views_map",
            ),
        ):
            changed = json.loads(json.dumps(document["cases"]))
            case = next(item for item in changed if item["id"] == case_id)
            mutation(case)
            self.assertIn(expected_error, run_matrix.validate_required_sentinels(changed))


if __name__ == "__main__":
    unittest.main()
