#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func collectionRemovalPreservesMembershipOfSetOperands(mode: EmitMode) throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
        let source = try String(contentsOf: fixtures.appendingPathComponent("collectionRemovalMembershipContracts.kt"), encoding: .utf8)
        let expected = try String(contentsOf: fixtures.appendingPathComponent("collectionRemovalMembershipContracts.out"), encoding: .utf8)
        try withWorkspace { root in
            let fixture = fixtures.deletingLastPathComponent().appendingPathComponent("JVMOwnStdlibInterop/CaseInsensitiveSets.java")
            try FileManager.default.copyItem(at: fixture, to: root.appendingPathComponent("CaseInsensitiveSets.java"))
            _ = try jvmTool("javac", ["-d", root.path, "CaseInsensitiveSets.java"], root: root)
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
}
#endif
