#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func listOfNotNullLinksBothOverloadsAgainstOwnStdlib() throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            fun main() {
                val missing: String? = null
                val present: String? = "one"
                println(listOfNotNull(missing))
                println(listOfNotNull(present))
                println(listOfNotNull(missing, "two", present, missing))
                val values: Array<String?> = arrayOf(null, "one", "one", null)
                println(listOfNotNull(*values))
                println(listOfNotNull<String>())
            }
            """, expected: "[]\n[one]\n[two, one]\n[one, one]\n[]\n", mode: .jvmJar, root: root)
        }
    }
}
#endif
