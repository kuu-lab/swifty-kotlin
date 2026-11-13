#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func annotatedCatchParameterPreservesExceptionBinding() throws {
        try withWorkspace { root in
            try runM11("""
            fun main() {
                try {
                    error("caught")
                } catch (@Suppress("SwallowedException") exception: IllegalStateException) {
                    println(exception.message)
                }
            }
            """, expected: "caught\n", mode: .jvmJar, root: root)
        }
    }
}
#endif
