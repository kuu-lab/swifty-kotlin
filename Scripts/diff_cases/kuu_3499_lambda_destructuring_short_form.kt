// KUU-3499: Name-based lambda destructuring short form accepts underscores and nested/stdlib lambdas.
// KOTLINC_FLAGS: -XXLanguage:+NameBasedDestructuring -XXLanguage:+DeprecateNameMismatchInShortDestructuringWithParentheses -XXLanguage:+EnableNameBasedDestructuringShortForm

class A {
    operator fun component1() = "O"
    operator fun component2(): String = throw RuntimeException("fail 0")
    operator fun component3() = "K"
}

fun foo(a: A, block: (A) -> String): String = block(a)

fun noop() {}

fun box(): String {
    val first = foo(A()) { [x, _, y] -> x + y }
    if (first != "OK") return "fail 1: $first"

    listOf(Pair("O", "K")).map { [a, b] -> { noop() } }
        .forEach { it() }

    val third = listOf("O", "K", "fail").let { [x, y] -> x + y }
    if (third != "OK") return "fail 2: $third"

    return "OK"
}

fun main() = println(box())
