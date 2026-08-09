// KSP-435: a bare Collection<T> receiver can be backed by either a list or a
// set box, so `size` / `isEmpty()` must dispatch on the runtime representation
// instead of assuming a list.
fun <T> report(values: Collection<T>) {
    println(values.size)
    println(values.isEmpty())
    println(values.toList().size)
    println(values.toMutableList().size)
}

fun main() {
    report(listOf("a", "b"))
    report(setOf("c"))
    report(emptyList<String>())
    report(emptySet<String>())

    val backing: Any = setOf("x", "y")
    println(backing is Iterable<*>)
    println(backing is Collection<*>)
    println(backing is Set<*>)

    val asCollection = backing as Collection<String>
    println(asCollection.size)
    println(asCollection.isEmpty())

    val letters: Collection<String> = setOf("p", "q", "r")
    val typed = letters.toTypedArray()
    println(typed.size)
    println(typed.joinToString("/"))

    val copied = letters.toList()
    println(copied)
    println(copied.size)
}
