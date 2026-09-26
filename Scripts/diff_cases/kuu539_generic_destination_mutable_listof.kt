fun <T, C : MutableCollection<in T>> collectInto(dest: C, value: T): C {
    dest.add(value)
    return dest
}

fun <T, C : MutableCollection<in T>> List<T>.drainInto(dest: C): C {
    for (item in this) dest.add(item)
    return dest
}

fun main() {
    val dest: MutableList<Int> = listOf(1, 2).mapTo(mutableListOf()) { it * 2 }
    println(dest)
    val undeclared = listOf(1, 2).mapTo(mutableListOf()) { it * 3 }
    println(undeclared)
    val generic = collectInto(mutableListOf(), 1)
    println(generic)
    val ext = listOf(1, 2).drainInto(mutableListOf())
    println(ext)
}
