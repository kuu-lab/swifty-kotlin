#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func unitLambdaResultIsBoxedForAny(mode: EmitMode) throws {
        try checkUnitObjectResultFixture("unitLambdaObjectResult", mode: mode)
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func unitObjectResultsPreserveEvaluationAndTermination(mode: EmitMode) throws {
        try checkUnitObjectResultFixture("unitObjectResultContracts", mode: mode)
    }

    private func checkUnitObjectResultFixture(_ name: String, mode: EmitMode) throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
        let source = try String(contentsOf: fixtures.appendingPathComponent(name + ".kt"), encoding: .utf8)
        let expected = try String(contentsOf: fixtures.appendingPathComponent(name + ".out"), encoding: .utf8)
        try withWorkspace { root in
            try runRuntimeParity(source, expected: expected, mode: mode, root: root)
        }
    }
}
#endif
