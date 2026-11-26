#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    /// KUU-4733: functions served by `JVMTextOperation.operations` failed under an
    /// aliased import ("Unsupported JVM member") and as callable references
    /// ("Missing JVM adapted reference target" / "Unsupported JVM callable
    /// reference target"), because both paths looked the table up by call-site name.
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
            }

            class Holder { fun indent(): (String) -> String = String::trimIndent }
            """, expected: "true\ntrue\n255\na\ntrue\ntrue\ntrue\nfalse\ntrue\nABC\ntrue\na\n43\n[true, false]\ntrimIndent\ntrue\nfalse\ny\ntrue\n", mode: mode, root: root)
        }
    }

    /// The bundled runtime's reflective `call` resolves a reference by owner
    /// and JVM signature, so text references point it at a generated bridge:
    /// the table row's own target may be an instance JDK method
    /// (`String.codePointAt`) or not exist at all (`uppercase` is emitted
    /// inline). Official kotlin-reflect resolves through Kotlin metadata
    /// instead and rejects these InlineOnly targets under kotlinc too, so this
    /// runs on the repository stdlib only (KUU-4733).
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func textOperationReferencesSupportReflectiveCallOnRepositoryStdlib(mode: EmitMode) throws {
        try repositoryStdlibRuntimeRegression(name: "textOperationReferenceCall", mode: mode)
    }
}
#endif
