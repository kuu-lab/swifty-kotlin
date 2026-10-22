#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func mutableCollectionAssignmentsUseMutationAndResolvedReassignment(mode: EmitMode) throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
        let source = try String(contentsOf: fixtures.appendingPathComponent("mutableCollectionAssignments.kt"), encoding: .utf8)
        let expected = try String(contentsOf: fixtures.appendingPathComponent("mutableCollectionAssignments.out"), encoding: .utf8)
        try withWorkspace { root in
            let fixture = fixtures.deletingLastPathComponent().appendingPathComponent("JVMOwnStdlibInterop/MutableCollectionOracle.java")
            try FileManager.default.copyItem(at: fixture, to: root.appendingPathComponent("MutableCollectionOracle.java"))
            _ = try jvmTool("javac", ["-d", root.path, "MutableCollectionOracle.java"], root: root)
            let library = try ownStdlibRuntime()
            let result = try compile(source, root: root, mode: mode, classpath: [root.path, library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-Xverify:all", "-cp", artifact + ":" + root.path + ":" + library.path, "HelloKt"])
            #expect(execution.stdout == expected)
            #expect(execution.stderr.isEmpty)
            _ = try jvmTool("kotlinc", ["hello.kt", "-classpath", root.path, "-d", "official.jar"], root: root)
            let foreign = try java(["-Xverify:all", "-cp", root.appendingPathComponent("official.jar").path + ":" + root.path + ":" + library.path, "HelloKt"])
            #expect(foreign.stdout == expected)
            #expect(foreign.stderr.isEmpty)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func collectionCompoundAssignmentsRejectReadOnlyValsAndWrongElements(mode: EmitMode) throws {
        let library = try ownStdlibRuntime()
        for (source, diagnostic) in [
            ("fun main() { val values = listOf(1); values += 2 }", "KSWIFTK-SEMA-0014"),
            ("fun main() { val values = mutableListOf(1); values += \"x\" }", "KSWIFTK-TYPE-0001"),
            ("fun main() { mutableListOf(1).addAll(arrayOf(\"x\")) }", "KSWIFTK-TYPE-0001"),
            ("fun main() { mutableListOf(1).removeAll(arrayOf(\"x\")) }", "KSWIFTK-TYPE-0001"),
        ] {
            try withWorkspace { root in
                let result = try compile(source, root: root, mode: mode, classpath: [library.path])
                #expect(result.0 != 0)
                #expect(result.1.contains { $0.severity == .error && $0.code == diagnostic })
                #expect(!result.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
            }
        }
    }

}
#endif
