#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kuu2703DefaultedTopLevelCallableReference(mode: EmitMode) throws {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/KUU-2703")
        let source = try String(
            contentsOf: fixtures.appendingPathComponent("defaultedTopLevelCallableReference.kt"),
            encoding: .utf8
        )
        let expected = try String(
            contentsOf: fixtures.appendingPathComponent("defaultedTopLevelCallableReference.out"),
            encoding: .utf8
        )

        try withWorkspace { root in
            try runM11(source, expected: expected, mode: mode, root: root)
        }
    }
}
#endif
