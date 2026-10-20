#!/usr/bin/env python3
"""Regression controls for the JVM runtime linkage audit (requires a JDK)."""
import pathlib
import subprocess
import sys
import tempfile
import unittest


AUDIT = pathlib.Path(__file__).resolve().parents[1] / "validate_jvm_stdlib.py"


class RuntimeLinkageAuditTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        self.parent = self.root / "Parent.java"
        self.consumer = self.root / "Consumer.java"
        self.parent.write_text('''package kotlin.probe;
public class Parent extends RuntimeException {
    public Parent() {}
    public Parent(String value) { super(value); }
    public static int present() { return 1; }
}''')
        self.consumer.write_text('''public class Consumer {
    public static String literal() { return "Lkotlin/nonexistent/Ghost;"; }
    public static int member() { return kotlin.probe.Parent.present(); }
    public static String inherited() { return new kotlin.probe.Parent("ok").getMessage(); }
}''')
        self.compile(self.parent, self.consumer)

    def compile(self, *sources):
        subprocess.run(["javac", "-d", str(self.root), *map(str, sources)], check=True, capture_output=True)

    def audit(self):
        return subprocess.run([sys.executable, str(AUDIT), str(self.root)], capture_output=True, text=True)

    def test_string_literals_and_real_inherited_jdk_methods(self):
        result = self.audit()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("0 unresolved references", result.stdout)

    def test_missing_member_is_not_supplied_by_external_superclass(self):
        consumer = self.root / "Consumer.class"
        data = consumer.read_bytes()
        self.assertIn(b"present", data)
        consumer.write_bytes(data.replace(b"present", b"missing"))
        result = self.audit()
        self.assertEqual(result.returncode, 1)
        self.assertIn("kotlin/probe/Parent.missing()I", result.stderr)
        self.assertNotIn("nonexistent/Ghost", result.stderr)

    def test_constructors_are_not_inherited(self):
        self.parent.write_text('package kotlin.probe; public class Parent extends RuntimeException { public Parent() {} public static int present() { return 1; } }')
        self.compile(self.parent)
        result = self.audit()
        self.assertEqual(result.returncode, 1)
        self.assertIn("kotlin/probe/Parent.<init>(Ljava/lang/String;)V", result.stderr)

    def test_array_class_tokens_require_the_element_class(self):
        ghost = self.root / "Ghost.java"
        ghost.write_text('package kotlin.probe; public class Ghost {}')
        self.consumer.write_text('public class Consumer { public static Class<?> array() { return kotlin.probe.Ghost[][].class; } }')
        self.compile(ghost, self.consumer)
        self.assertEqual(self.audit().returncode, 0)
        (self.root / "kotlin/probe/Ghost.class").unlink()
        result = self.audit()
        self.assertEqual(result.returncode, 1)
        self.assertIn("missing class kotlin/probe/Ghost", result.stderr)


if __name__ == "__main__":
    unittest.main()
