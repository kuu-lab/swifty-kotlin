#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func importedObjectMembersKeepTheirSingletonInNullableExtensions(mode: EmitMode) throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
        let source = try String(contentsOf: fixtures.appendingPathComponent("objectImportedDispatchReceivers.kt"), encoding: .utf8)
        let expected = try String(contentsOf: fixtures.appendingPathComponent("objectImportedDispatchReceivers.out"), encoding: .utf8)
        try withWorkspace { root in
            try runRuntimeParity(source, expected: expected, mode: mode, root: root)
        }
    }
}
#endif
