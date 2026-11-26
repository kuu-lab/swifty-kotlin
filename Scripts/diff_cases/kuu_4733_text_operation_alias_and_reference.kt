// DIFF_JVM
// KUU-4733: JVM text-table operations reached through an aliased import or a
// callable reference. An aliased import hides the original name in this file,
// so references below use the other table functions (and the alias itself).
import kotlin.text.endsWith as ew
import kotlin.text.substringBefore as before
import kotlin.text.toInt as asInt
import kotlin.text.trim as tr

fun String.selfRef(): (String) -> Boolean = this::ew

suspend fun main() {
    println("abc".ew("c"))
    println("abc".ew("C", ignoreCase = true))
    println("a,b".before(","))
    println("ff".asInt(16))
    println("xxaxx".tr('x'))
    val nullable: String? = "abc"
    println(nullable?.ew("c"))
    println(with("hello") { ew("lo") })

    val boundDefault: (String) -> Boolean = "abc"::ew
    println(boundDefault("bc"))
    val unboundDefault: (String, String) -> Boolean = String::ew
    println(unboundDefault("abc", "b"))
    val exact: (String, String, Boolean) -> Boolean = String::ew
    println(exact("abc", "C", true))
    val sequence: (CharSequence, CharSequence) -> Boolean = CharSequence::ew
    println(sequence(StringBuilder("xyz"), "yz"))
    val upper: (String) -> String = String::uppercase
    println(upper("abc"))
    val indent: (String) -> String = String::trimIndent
    println(indent("  x"))
    val take: (String, Int) -> String = String::take
    println(take("abcdef", 3))
    val empty: (String) -> Boolean = String::isEmpty
    println(empty(""))
    val notBlank: () -> Boolean = "hello"::isNotBlank
    println(notBlank())
    val trimChars: (String, CharArray) -> String = String::tr
    println(trimChars("--a--", charArrayOf('-')))
    val split: (String, Array<out String>) -> List<String> = String::split
    println(split("a,b;c", arrayOf(",", ";")))
    val pad: (String, Int) -> String = String::padStart
    println(pad("7", 3) + "|")
    val parse: (String) -> Int = String::asInt
    println(parse("42") + 1)
    val substring: (String, Int, Int) -> String = String::substring
    println(substring("abcdef", 1, 3))
    val discard: (String) -> Unit = String::uppercase
    discard("x")
    println("done".selfRef()("ne"))
    println(listOf("x", "").map(String::isNotEmpty))
    val named = String::trimIndent
    println(named.name)
    val contains: (CharSequence, CharSequence) -> Boolean = CharSequence::contains
    println(contains("abc", "b"))
    val containsChar: (CharSequence, Char) -> Boolean = CharSequence::contains
    println(containsChar("abc", 'z'))
    val suspended: suspend (String) -> String = String::trimIndent
    println(suspended("   y"))
    val codePoint = String::codePointAt
    println(codePoint("abc", 1))
}
