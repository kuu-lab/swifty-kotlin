// DIFF_JVM
fun main() {
    val values = listOf(1, 2, 3)
    println(values.lastIndex)
    println(values.indices.toList())

    val empty = emptyList<Int>()
    println(empty.lastIndex)
    println(empty.indices.toList())

    println("abc".lastIndex)
    println("".lastIndex)
    val sequence: CharSequence = "abc"
    println(sequence.indices.toList())
    val emptySequence: CharSequence = ""
    println(emptySequence.indices.toList())
}
