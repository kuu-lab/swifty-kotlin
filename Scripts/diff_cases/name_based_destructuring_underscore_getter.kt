// KOTLINC_FLAGS: -XXLanguage:+NameBasedDestructuring -XXLanguage:+DeprecateNameMismatchInShortDestructuringWithParentheses -XXLanguage:+EnableNameBasedDestructuringShortForm

object O {
    var counter = 0
    val first: Int get() = counter++
}

fun main() {
    val (_ = first) = O
    println(O.counter)
}
