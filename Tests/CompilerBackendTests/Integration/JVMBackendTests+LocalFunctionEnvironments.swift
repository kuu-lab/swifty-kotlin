#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func localFunctionsPreserveEnvironmentsRecursionAndNormalReturns(mode: EmitMode) throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
        let source = try String(contentsOf: fixtures.appendingPathComponent("localFunctionEnvironmentContracts.kt"), encoding: .utf8)
        let expected = try String(contentsOf: fixtures.appendingPathComponent("localFunctionEnvironmentContracts.out"), encoding: .utf8)
        try withWorkspace { root in
            let compiled = try compile(source, root: root, mode: mode)
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-cp", artifact + ":" + (try m11Runtime()), "HelloKt"])
            #expect(execution.stdout == expected)
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
