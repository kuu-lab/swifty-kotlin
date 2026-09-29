class Key(val id: Int, val tag: Int) {
    override fun equals(other: Any?) = other is Key && other.id == id
    override fun hashCode() = id
}

fun main() {
    println(Key(1, 1) == Key(1, 2))
    println(setOf(Key(1, 1), Key(1, 2)).size)
    println(listOf(Key(1, 1)).indexOf(Key(1, 2)))
    val m = mutableMapOf(Key(1, 1) to "a")
    m[Key(1, 2)] = "b"
    println(m.size)
    println(listOf(Key(2, 0), Key(2, 9)).distinct().size)
    println(Key(3, 0) in listOf(Key(3, 5)))
}
