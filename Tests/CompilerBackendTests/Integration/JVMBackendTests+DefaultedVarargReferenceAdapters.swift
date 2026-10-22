#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func defaultedVarargCallableReferencesEvaluateDefaultsAtInvocation(mode: EmitMode) throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
        let source = try String(contentsOf: fixtures.appendingPathComponent("defaultedVarargCallableReferenceAdapters.kt"), encoding: .utf8)
        let expected = try String(contentsOf: fixtures.appendingPathComponent("defaultedVarargCallableReferenceAdapters.out"), encoding: .utf8)
        try withWorkspace { root in
            try runM11(source, expected: expected, mode: mode, root: root)
        }
        try repositoryStdlibRuntimeRegression(name: "defaultedVarargCallableReferenceAdapters", mode: mode)
    }
}
#endif
