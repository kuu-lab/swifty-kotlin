#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func reflectionParameterNamesUseParameterOwner(mode: EmitMode) throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
        let source = try String(contentsOf: fixtures.appendingPathComponent("reflectionParameterNames.kt"), encoding: .utf8)
        let expected = try String(contentsOf: fixtures.appendingPathComponent("reflectionParameterNames.out"), encoding: .utf8)
        try withWorkspace { root in
            try runM11(source, expected: expected, mode: mode, root: root)
        }
        try repositoryStdlibRuntimeRegression(name: "reflectionParameterNames", mode: mode)
    }
}
#endif
