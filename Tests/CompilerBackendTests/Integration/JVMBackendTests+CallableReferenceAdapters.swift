#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func nonReifiedCallableReferenceAdapters(mode: EmitMode) throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
        let source = try String(contentsOf: fixtures.appendingPathComponent("nonReifiedCallableReferenceAdapters.kt"), encoding: .utf8)
        let expected = try String(contentsOf: fixtures.appendingPathComponent("nonReifiedCallableReferenceAdapters.out"), encoding: .utf8)
        try withWorkspace { root in
            try runM11(source, expected: expected, mode: mode, root: root)
        }
        try repositoryStdlibRuntimeRegression(name: "nonReifiedCallableReferenceAdapters", mode: mode)
    }
}
#endif
