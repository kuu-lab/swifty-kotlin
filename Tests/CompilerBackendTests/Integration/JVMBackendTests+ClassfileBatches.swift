#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func sizeBalancedClasspathBatchesKeepEveryClass() throws {
        try withWorkspace { root in
            let source = root.appendingPathComponent("Batch.java")
            var lines = ["package probe;", "public class Batch {"]
            for index in 0..<180 {
                let body = index.isMultiple(of: 35)
                    ? "public static final String TEXT = \"\(String(repeating: "a", count: 16_000))\";"
                    : ""
                lines.append("public static class Entry\(index) { \(body) }")
            }
            lines.append("}")
            try lines.joined(separator: "\n").write(to: source, atomically: true, encoding: .utf8)
            let classes = root.appendingPathComponent("classes")
            try FileManager.default.createDirectory(at: classes, withIntermediateDirectories: true)
            let compiled = try javac(["--release", "8", "-d", classes.path, source.path])
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let archive = root.appendingPathComponent("batch.jar")
            let packaged = try jvmTool("jar", ["--create", "--file", archive.path, "-C", classes.path, "."], root: root)
            try #require(packaged.exitCode == 0, "\(packaged.stderr)")

            let sequential = try JVMClasspathIndex.load([archive.path], archiveJobs: 1)
            let parallel = try JVMClasspathIndex.load([archive.path], archiveJobs: 4)
            #expect(parallel.classes.count == 181)
            #expect(Set(sequential.classes.keys) == Set(parallel.classes.keys))
            #expect(parallel.classes["probe/Batch$Entry175"]?.fields.first?.constantValue != nil)
        }
    }
}
#endif
