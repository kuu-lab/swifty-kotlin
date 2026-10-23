#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func integerBitOperationsExecuteFromBundledJVMStdlib(mode: EmitMode) throws {
        try withWorkspace { root in
            let fixtures = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures/JVMOwnStdlib")
            let source = try String(contentsOf: fixtures.appendingPathComponent("integerBitOperations.kt"), encoding: .utf8)
            let expected = try String(contentsOf: fixtures.appendingPathComponent("integerBitOperations.out"), encoding: .utf8)
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            let arguments = mode == .jvmJar
                ? ["-jar", root.appendingPathComponent("hello.jar").path]
                : ["-cp", root.appendingPathComponent("classes").path, "HelloKt"]
            let execution = try java(arguments)
            #expect(execution.stdout == expected)
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
