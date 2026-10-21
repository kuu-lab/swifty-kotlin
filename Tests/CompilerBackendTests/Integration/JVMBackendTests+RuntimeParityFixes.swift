#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    private func runJVMOwnStdlibFixture(_ name: String, mode: EmitMode) throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
        let source = try String(contentsOf: fixtures.appendingPathComponent(name + ".kt"), encoding: .utf8)
        let expected = try String(contentsOf: fixtures.appendingPathComponent(name + ".out"), encoding: .utf8)
        try withWorkspace { root in
            let library = try ownStdlibRuntime()
            let result = try compile(source, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-Xverify:all", "-cp", artifact + ":" + library.path, "HelloKt"])
            #expect(execution.stdout == expected)
            #expect(execution.stderr.isEmpty)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func nullableScalarObjectMethodsAreNullSafe(mode: EmitMode) throws {
        try runJVMOwnStdlibFixture("nullableScalarObjectMethods", mode: mode)
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func inferredIntRangeReceiverKeepsRangeType(mode: EmitMode) throws {
        try runJVMOwnStdlibFixture("inferredIntRangeReceiver", mode: mode)
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func nullCastThrowsKotlinCompatibleMessage(mode: EmitMode) throws {
        try runJVMOwnStdlibFixture("nullCastExceptionMessage", mode: mode)
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func callableReferenceToStringRendersFullSignature(mode: EmitMode) throws {
        try runJVMOwnStdlibFixture("callableReferenceToString", mode: mode)
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func collectionFactoriesMatchKotlincJavaClass(mode: EmitMode) throws {
        try runJVMOwnStdlibFixture("collectionFactoryJavaClass", mode: mode)
    }
}
#endif
