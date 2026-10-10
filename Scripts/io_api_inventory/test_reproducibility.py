#!/usr/bin/env python3
"""Check that the ledger survives relocation and filesystem creation order."""

import importlib.util
import shutil
import tempfile
import unittest
from pathlib import Path


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]


def load_generator(path):
    spec = importlib.util.spec_from_file_location("io_inventory_generator", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def rendered_outputs(module):
    lock, rows, scopes = module.build_outputs()
    return (
        module.render_tsv(module.LEDGER_PATH, module.LEDGER_COLUMNS, rows),
        module.render_tsv(module.SCOPE_PATH, module.SCOPE_COLUMNS, scopes),
        module.make_summary(lock, rows, scopes),
    )


class ReproducibilityTests(unittest.TestCase):
    def test_relocated_checkout_with_reverse_creation_order_matches(self):
        original = load_generator(HERE / "generate.py")
        expected = rendered_outputs(original)
        with tempfile.TemporaryDirectory(prefix="io-inventory-relocated-") as temporary:
            relocated = Path(temporary) / "checkout"
            inputs = list(HERE.rglob("*"))
            inputs.extend((REPO / "Sources/CompilerCore/Stdlib/kotlinx/io").rglob("*.kt"))
            test_inputs = list((REPO / "Tests").rglob("*.swift"))
            test_inputs.extend((REPO / "Tests/CompilerCoreTests/GoldenCases/Sema").glob("*.kt"))
            test_inputs.extend((REPO / "Scripts/diff_cases").glob("*.kt"))
            inputs.extend(
                path for path in test_inputs
                if path.relative_to(REPO).as_posix().startswith(original.LOCAL_IO_TEST_PREFIXES)
            )
            for source in sorted(set(inputs), reverse=True):
                if not source.is_file() or "__pycache__" in source.parts:
                    continue
                destination = relocated / source.relative_to(REPO)
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, destination)
            generator = relocated / "Scripts/io_api_inventory/generate.py"
            self.assertEqual(rendered_outputs(load_generator(generator)), expected)

    def test_source_array_inventory_links_existing_kotlin_regressions(self):
        generator = load_generator(HERE / "generate.py")
        _, rows, _ = generator.build_outputs()
        declaration = next(
            row for row in rows
            if row.get("_api_id") == "kotlinx.io/readByteArray|readByteArray@kotlinx.io.Source(kotlin.Int){}"
        )
        references = declaration["local_test_refs"].split(";")
        self.assertIn("Tests/CompilerCoreTests/GoldenCases/Sema/kotlinx_io_sources_surface.kt", references)
        self.assertIn("Scripts/diff_cases/kotlinx_io_sources_arrays.kt", references)


if __name__ == "__main__":
    unittest.main()
