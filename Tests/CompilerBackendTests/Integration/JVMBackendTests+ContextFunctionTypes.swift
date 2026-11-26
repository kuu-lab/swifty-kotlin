#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func contextualFunctionTypeAnnotationsCompileAndRunOnJvm() throws {
        try withWorkspace { root in
            try runM11(
                """
                fun main() {
                    val f: context(String) () -> String = context(a: String) fun() = a
                    println(f("O"))
                }
                """,
                expected: "O\n",
                mode: .jvmJar,
                root: root
            )
        }
    }
}
#endif
