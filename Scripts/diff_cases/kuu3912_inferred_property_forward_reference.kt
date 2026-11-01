// KUU-3912 (ktor-http IpParser.kt): top-level `val`s whose types are only
// inferred kept their header-registered Any? placeholder while a reader
// declared earlier in the file (or compiled in an earlier-processed file)
// resolved members on them, failing with KSWIFTK-SEMA-0024. kotlinc accepts
// every shape below; the safe precheck now publishes the inferred type before
// the reader's pass runs.

internal class Grammar {
    fun member(input: String): Boolean = input.isNotEmpty()
}
internal infix fun Grammar.or(other: Grammar): Grammar = this
internal fun Grammar.match(input: String): Boolean = member(input)

// Function declared before the inferred properties it reads.
fun hostIsIp(host: String): Boolean =
    GETTER_GRAMMAR.member(host)
        && INFIX_GRAMMAR.match(host)
        && LIST.isNotEmpty()
        && PAIR.first.isNotEmpty()
        && PAIR.second > 0

// Inferred properties declared after their readers.
internal val GETTER_GRAMMAR get() = Grammar()
internal val INFIX_GRAMMAR = Grammar() or Grammar()
internal val LIST = listOf("")
internal val PAIR = Pair("k", 1)

fun main() {
    println(hostIsIp("127.0.0.1"))
    println(hostIsIp(""))
}
