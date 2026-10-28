@testable import CompilerCore
import TestStdlibCache
import Testing

@Suite(.serialized)
struct KUU3623ValueClassMemberExtensionPropertyTests {
    @Test
    func memberExtensionPropertyMayReuseBackingFieldName() throws {
        TestStdlibCache.shared.prepare()

        try compileAndRunKotlin(
            """
            // KUU-3623: the member extension is distinct from the constructor-backed property.
            value class Z(val s: String) {
                val Int.s: Int get() = 42
            }

            fun main() { println(Z("a").toString() == "Z(s=a)") }
            """,
            expectedOutput: "true\n",
            moduleName: "KUU3623ValueClassMemberExtensionProperty"
        )
    }
}
