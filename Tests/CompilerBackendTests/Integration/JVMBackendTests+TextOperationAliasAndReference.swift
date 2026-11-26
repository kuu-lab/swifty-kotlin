#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func textOperationsResolveThroughAliasedImportsAndCallableReferences(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            import kotlin.text.endsWith as ew
            import kotlin.text.toInt as asInt
            import kotlin.text.trim as tr

            suspend fun main() {
                println("abc".ew("c"))
                println("abc".ew("C", ignoreCase = true))
                println("ff".asInt(16))
                println("xxaxx".tr('x'))
                val nullable: String? = "abc"
                println(nullable?.ew("c"))
                println(with("hello") { ew("lo") })
                val boundDefault: (String) -> Boolean = "abc"::ew
                println(boundDefault("bc"))
                val unboundDefault: (String, String) -> Boolean = String::ew
                println(unboundDefault("abc", "b"))
                val sequence: (CharSequence, CharSequence) -> Boolean = CharSequence::ew
                println(sequence(StringBuilder("xyz"), "yz"))
                val upper: (String) -> String = String::uppercase
                println(upper("abc"))
                val notBlank: () -> Boolean = "hello"::isNotBlank
                println(notBlank())
                val trimChars: (String, CharArray) -> String = String::tr
                println(trimChars("--a--", charArrayOf('-')))
                val parse: (String) -> Int = String::asInt
                println(parse("42") + 1)
                val discard: (String) -> Unit = String::uppercase
                discard("x")
                println(listOf("x", "").map(String::isNotEmpty))
                println(String::trimIndent.name)
                val contains: (CharSequence, CharSequence) -> Boolean = CharSequence::contains
                println(contains("abc", "b"))
                val containsChar: (CharSequence, Char) -> Boolean = CharSequence::contains
                println(containsChar("abc", 'z'))
                val suspended: suspend (String) -> String = String::trimIndent
                println(suspended("   y"))
                println((String::trimIndent as (String) -> String) == Holder().indent())
                val same: (CharSequence, CharSequence?) -> Boolean = CharSequence::contentEquals
                println(same("a", null))
                println(same(StringBuilder("ab"), "ab"))
                val sameCase: (CharSequence, CharSequence?, Boolean) -> Boolean = CharSequence::contentEquals
                println(sameCase("AB", "ab", true))
                val nothing: String? = null
                val boundNull: (CharSequence?) -> Boolean = nothing::contentEquals
                println(boundNull(null))
                println(boundNull("a"))
                val strip: (String, Char, Char) -> String = String::tr
                println(strip("-+a+-", '-', '+'))
                val strip2: (String, Char, Char) -> String = String::tr
                println(strip == strip2)
                val splitTwo: (String, String, String) -> List<String> = String::split
                println(splitTwo("a,b;c", ",", ";"))
            }

            class Holder { fun indent(): (String) -> String = String::trimIndent }
            """, expected: "true\ntrue\n255\na\ntrue\ntrue\ntrue\nfalse\ntrue\nABC\ntrue\na\n43\n[true, false]\ntrimIndent\ntrue\nfalse\ny\ntrue\nfalse\ntrue\ntrue\ntrue\nfalse\na\ntrue\n[a, b, c]\n", mode: mode, root: root)
        }
    }
}
#endif
