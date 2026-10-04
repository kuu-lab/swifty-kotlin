fun main() {
    val empty = HashSet<String>()
    println(empty.isEmpty())
    val sized = HashSet<String>(4)
    println(sized.add("one"))
    println(sized.contains("one"))
    val copied = HashSet(listOf("a", "b", "a"))
    println(copied.size)
    val tuned = HashSet<Int>(2, 0.5f)
    println(tuned.add(5))
    println(tuned.contains(5))
    try {
        HashSet<Int>(-1)
        println("unexpected capacity")
    } catch (e: IllegalArgumentException) {
        println("capacity rejected")
    }
    try {
        HashSet<Int>(2, 0.0f)
        println("unexpected load factor")
    } catch (e: IllegalArgumentException) {
        println("load factor rejected")
    }
}
