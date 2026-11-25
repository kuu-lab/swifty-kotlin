#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Testing

extension JVMBackendTests {
    /// KUU-4648: `CharSequence?.contentEquals` used to be unresolved on the JVM backend
    /// (KSWIFTK-SEMA-0024) because only the Native bundled stdlib declared it.
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func charSequenceContentEqualsResolvesWithNullableReceiverAndIgnoreCase(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun main() {
                val nullableNull: String? = null
                val nullableA: String? = "abc"
                val nullableUpper: String? = "ABC"
                println(nullableNull.contentEquals(null))
                println(nullableNull.contentEquals(nullableA))
                println(nullableA.contentEquals(null))
                println(nullableA.contentEquals(nullableUpper))
                println(nullableA.contentEquals(nullableUpper, true))
                println(nullableA.contentEquals(nullableUpper, false))
                println(sameText(StringBuilder("abc"), "abc"))
                println(sameText(StringBuilder("abc"), "abd"))
                println("".contentEquals(null))
                println("".contentEquals(""))
                println("abc".contentEquals("abcd", true))
            }

            fun sameText(left: CharSequence, right: CharSequence?): Boolean = left contentEquals right
            """, expected: "true\nfalse\nfalse\nfalse\ntrue\nfalse\ntrue\nfalse\nfalse\ntrue\nfalse\n", mode: mode, root: root)
        }
    }
}
#endif
