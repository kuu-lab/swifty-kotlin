#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func downToProgressionUsesJvmFactory(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11(
                "fun main() { println((10 downTo 1).toList()) }",
                expected: "[10, 9, 8, 7, 6, 5, 4, 3, 2, 1]\n",
                mode: mode,
                root: root
            )
        }
    }
}
#endif
