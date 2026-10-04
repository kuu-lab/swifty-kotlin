fun main() {
    // `Collection<T>`/`Set<T>`-typed receivers have no registered joinToString
    // symbol of their own (unlike List), so a call never resolves to a real Sema
    // symbol. The KIR-lowering "unresolved member" fallback used to only admit
    // Sequence and (nominally) Iterable receivers for this, so Collection/Set
    // fell through all the way to a call on the literal, undefined external
    // symbol "joinToString" and failed at link time.
    val collection: Collection<Int> = listOf(1, 2, 3)
    println(collection.joinToString())
    println(collection.joinToString(" | "))
    println(collection.joinToString(prefix = "<", postfix = ">"))
    println(collection.joinToString(separator = ":", prefix = "[", postfix = "]"))

    val set: Set<String> = setOf("x", "y")
    println(set.joinToString(";"))
    println(set.joinToString(",") { it.uppercase() })

    val iter: Iterable<String> = listOf("a", "bb", "ccc")
    println(iter.joinToString("-") { "<" + it + ">" })
}
