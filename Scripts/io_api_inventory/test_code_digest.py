#!/usr/bin/env python3
"""Check that the comment-insensitive digest pins code, not comments."""

import shutil
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))

from code_digest import code_sha256, strip_comments  # noqa: E402
from source_index import SourceIndex  # noqa: E402


class DigestTests(unittest.TestCase):
    def digest(self, text, language="swift"):
        return code_sha256(text.encode("utf-8"), language)

    def test_comment_edits_keep_the_digest(self):
        base = "let a = 1\nfunc f() -> Int { a }\n"
        edited = (
            "// why: a comment\n"
            "let a = 1 // trailing\n"
            "/* block\n   /* nested */ still a comment */\n"
            "/// doc comment\n"
            "func f() -> Int { a }\n"
        )
        self.assertEqual(self.digest(base), self.digest(edited))
        self.assertEqual(self.digest(edited), self.digest(base))

    def test_code_edits_change_the_digest(self):
        self.assertNotEqual(self.digest("let a = 1\n"), self.digest("let a = 2\n"))
        self.assertNotEqual(self.digest("let a = 1\n"), self.digest("let a = 1\nlet b = 2\n"))

    def test_token_separating_whitespace_is_significant(self):
        self.assertNotEqual(self.digest("let f = @convention(c) () -> Void"),
                            self.digest("let f =@convention(c) () -> Void"))

    def test_layout_only_whitespace_is_not(self):
        self.assertEqual(self.digest("let a = 1\n\n\nlet b = 2\n"), self.digest("let a = 1\nlet b = 2\n"))

    def test_comment_markers_inside_string_literals_are_code(self):
        self.assertNotEqual(self.digest('let s = "a // b"\n'), self.digest('let s = "a "\n'))
        self.assertNotEqual(self.digest('let s = #"a /* b */"#\n'), self.digest('let s = #"a "#\n'))
        self.assertNotEqual(self.digest('let s = """\n// b\n"""\n'), self.digest('let s = """\n\n"""\n'))
        self.assertIn("//", strip_comments('let s = "a // b"\n', "swift"))

    def test_kotlin_literals(self):
        self.assertNotEqual(self.digest("val s = \"\"\"a // b\"\"\"\n", "kt"), self.digest("val s = \"\"\"a \"\"\"\n", "kt"))
        self.assertNotEqual(self.digest("val c = '/'\n", "kt"), self.digest("val c = '\\\\'\n", "kt"))
        self.assertEqual(self.digest("/** KDoc */\nval a = 1\n", "kt"), self.digest("val a = 1\n", "kt"))

    def test_unsupported_language_is_rejected(self):
        with self.assertRaises(ValueError):
            code_sha256(b"x", "java")


class CatalogIntegrationTests(unittest.TestCase):
    """The runtime pins in the checked-in catalog must survive comment-only edits and reject code edits."""

    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="io-code-digest-")
        cls.checkout = Path(cls.temporary.name) / "checkout"
        ignore = shutil.ignore_patterns("__pycache__")
        for relative in ("Scripts/io_api_inventory", "Sources/Runtime", "Sources/CompilerCore/Stdlib/kotlinx/io"):
            shutil.copytree(REPO / relative, cls.checkout / relative, ignore=ignore)
        cls.runtime = sorted((cls.checkout / "Sources/Runtime").rglob("*.swift"))

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def load(self):
        inventory = self.checkout / "Scripts/io_api_inventory"
        return SourceIndex(
            inventory / "source-declarations.json", self.checkout, inventory / "upstream/kotlinx-io-0.9.1"
        )

    def test_comment_only_runtime_edit_is_accepted_and_code_edit_is_rejected(self):
        target = self.runtime[0]
        original = target.read_text(encoding="utf-8")
        try:
            self.load()
            target.write_text("// why: a comment-only edit\n" + original + "\n// trailing note\n", encoding="utf-8")
            self.load()
            target.write_text(original + "\nlet digestTestCodeEdit = 1\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "Runtime implementation catalog inputs changed"):
                self.load()
        finally:
            target.write_text(original, encoding="utf-8")


if __name__ == "__main__":
    unittest.main()
