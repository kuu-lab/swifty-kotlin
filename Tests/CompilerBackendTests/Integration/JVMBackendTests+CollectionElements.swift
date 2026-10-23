#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func collectionElementAccessPreservesEmptyAndIteratorContracts(mode: EmitMode) throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
        let source = try String(contentsOf: fixtures.appendingPathComponent("JVMOwnStdlib/collectionElementAccessContracts.kt"), encoding: .utf8)
        let expected = try String(contentsOf: fixtures.appendingPathComponent("JVMOwnStdlib/collectionElementAccessContracts.out"), encoding: .utf8)
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let oracle = fixtures.appendingPathComponent("JVMOwnStdlibInterop/ElementAccessOracle.java")
            _ = try jvmTool("javac", ["-d", root.path, oracle.path], root: root)
            let compiled = try compile(source, root: root, mode: mode, classpath: [library.path, root.path])
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            _ = try jvmTool("kotlinc", ["hello.kt", "-classpath", root.path, "-d", "reference.jar"], root: root)
            let reference = root.appendingPathComponent("reference.jar")
            for classpath in [artifact.path + ":" + library.path,
                              reference.path + ":" + library.path,
                              reference.path + ":" + (try m11Runtime())] {
                let result = try java(["-Xverify:all", "-cp", root.path + ":" + classpath, "HelloKt"])
                #expect(result.exitCode == 0)
                #expect(result.stdout == expected)
                #expect(result.stderr.isEmpty)
            }
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func hashCollectionElementAccessOriginalUsesOnlyRepositoryRuntime(mode: EmitMode) throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
        let source = try diffCaseSource("arch010_hash_collections.kt")
        let expected = try String(contentsOf: fixtures.appendingPathComponent("hashCollectionElementAccessOriginal.out"), encoding: .utf8)
        try withWorkspace { root in
            try runRuntimeParity(source, expected: expected, mode: mode, root: root)
        }
    }
}
#endif
