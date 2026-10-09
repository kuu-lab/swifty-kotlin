import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import reference


class ReferenceIntegrityTests(unittest.TestCase):
    def test_pinned_inventory_preserves_targets_and_all_modules(self):
        manifest = reference.read_manifest()
        reference.verify_files(reference.ROOT, manifest)
        reference.verify_index(reference.ROOT, manifest)
        rows = reference.declarations(reference.ROOT, manifest)["declarations"]
        self.assertEqual({row["module"] for row in rows},
                         {"core", "json", "cbor", "protobuf", "properties", "json-io", "json-okio", "hocon"})
        self.assertTrue(all(row["implementation"] == "unmapped" for row in rows))
        js_view = next(row for row in rows if row["module"] == "json" and row["platform"] == "klib"
                       and "asJsReadonlyArrayView" in row["signature"])
        builder = next(row for row in rows if row["module"] == "json" and row["platform"] == "klib"
                       and "class kotlinx.serialization.json/JsonArrayBuilder" in row["signature"])
        self.assertEqual(js_view["targets"], ["js"])
        self.assertIn("macosArm64", builder["targets"])
        self.assertGreater(len(builder["targets"]), 1)
        maps = [row for row in rows if row["module"] == "core" and row["platform"] == "klib"
                and "class <#A:" in row["signature"] and "/LinkedHashMapSerializer :" in row["signature"]]
        self.assertEqual(len(maps), 2)
        self.assertNotEqual(maps[0]["id"], maps[1]["id"])
        self.assertIn("macosArm64", maps[0]["targets"])
        self.assertEqual(maps[1]["targets"], ["js"])
        json_internal = [row for row in rows if row["module"] == "json" and
                         ("serialization/json/internal/" in row["owner"] + row["signature"] or
                          "serialization.json.internal/" in row["owner"] + row["signature"])]
        self.assertTrue(json_internal)
        self.assertTrue(all("exported-internal-package" in row["classification"] for row in json_internal))

    def test_target_annotation_applies_to_one_declaration_and_children(self):
        source = """// Targets: [linuxX64, js]
// Alias: native => [linuxX64]
final class sample/Foo {
    // Targets: [js]
    final val jsOnly
        final fun <get-jsOnly>(): kotlin/Int
    final fun common(): kotlin/Int
}
// Targets: [native]
final class sample/Native {
    final fun method(): kotlin/Int
}
final class sample/Common {}
"""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "fixture.api").write_text(source)
            manifest = {"commit": "fixture", "files": [{"module": "core", "platform": "klib", "path": "fixture.api"}]}
            rows = reference.declarations(root, manifest)["declarations"]
        self.assertEqual([row["targets"] for row in rows], [
            ["js", "linuxX64"], ["js"], ["js"], ["js", "linuxX64"],
            ["linuxX64"], ["linuxX64"], ["js", "linuxX64"],
        ])

    def test_modified_upstream_and_stale_index_are_rejected(self):
        data = b"original\n"
        blob = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
        manifest = {"files": [{"path": "source.api", "sha256": reference.sha256(data), "git_blob": blob}]}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "source.api").write_bytes(data)
            reference.verify_files(root, manifest)
            (root / "source.api").write_bytes(data + b"tampered")
            with self.assertRaisesRegex(ValueError, "Upstream hash mismatch"):
                reference.verify_files(root, manifest)
            (root / "declarations.json").write_text("{}\n")
            with self.assertRaisesRegex(ValueError, "index is stale"):
                reference.verify_index(root, {"commit": "fixture", "files": []})

    def test_corrupt_or_missing_artifacts_fail_before_execution(self):
        data = b"fixture artifact"
        record = {"filename": "fixture.jar", "bytes": len(data), "sha256": reference.sha256(data),
                  "published_sha1": hashlib.sha1(data).hexdigest(), "url": "https://example.invalid/fixture.jar"}
        manifest = {"artifacts": [record]}
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            with self.assertRaises(FileNotFoundError):
                reference.verify_artifacts(cache, manifest)
            (cache / "fixture.jar").write_bytes(data + b"tampered")
            with patch.object(reference.urllib.request, "urlopen") as network:
                with self.assertRaisesRegex(ValueError, "Artifact hash mismatch"):
                    reference.fetch_artifacts(cache, manifest)
                network.assert_not_called()
            with patch.object(reference.subprocess, "run") as command:
                with self.assertRaisesRegex(ValueError, "Artifact hash mismatch"):
                    reference.run_reference(cache, manifest, cache, cache, cache)
                command.assert_not_called()

    def test_published_checksum_and_locked_sha256_both_required(self):
        data = b"fixture artifact"
        record = {"filename": "fixture.jar", "bytes": len(data), "sha256": reference.sha256(data),
                  "published_sha1": hashlib.sha1(data).hexdigest(), "url": "https://example.invalid/fixture.jar"}
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            with patch.object(reference.urllib.request, "urlopen", side_effect=[io.BytesIO(data), io.BytesIO(b"0" * 40)]):
                with self.assertRaisesRegex(ValueError, "Published checksum mismatch"):
                    reference.fetch_artifacts(cache, {"artifacts": [record]})
            self.assertFalse((cache / "fixture.jar").exists())
            wrong_lock = dict(record, sha256="0" * 64)
            with patch.object(reference.urllib.request, "urlopen", side_effect=[io.BytesIO(data), io.BytesIO(record["published_sha1"].encode())]):
                with self.assertRaisesRegex(ValueError, "Artifact hash mismatch"):
                    reference.fetch_artifacts(cache, {"artifacts": [wrong_lock]})
            self.assertFalse((cache / "fixture.jar").exists())
            with patch.object(reference.urllib.request, "urlopen", side_effect=[io.BytesIO(data), io.BytesIO(record["published_sha1"].encode())]):
                reference.fetch_artifacts(cache, {"artifacts": [record]})
            self.assertEqual((cache / "fixture.jar").read_bytes(), data)


if __name__ == "__main__":
    unittest.main()
