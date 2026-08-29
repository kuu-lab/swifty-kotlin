fun main() {
    val singleton: Set<Int> = setOf(1)
    val nullableSingleton: Set<String?> = setOf(null as String?)
    val nonNullSingleton: Set<String> = setOfNotNull("a")
    val empty: Set<String> = setOfNotNull<String>()
    val allNull: Set<String> = setOfNotNull<String>(null, null)
    val mixed: Set<String> = setOfNotNull("a", null, "b", "a")
    val source: Array<String?> = arrayOf("x", null, "y", "x")
    val spread: Set<String> = setOfNotNull(*source)

    println(singleton.contains(1))
    println(nullableSingleton.contains(null))
    println(nonNullSingleton)
    println(empty.isEmpty())
    println(allNull.isEmpty())
    println(mixed)
    println(spread)
}
