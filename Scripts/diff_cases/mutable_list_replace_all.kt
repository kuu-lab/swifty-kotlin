// DIFF_JVM
fun main() {
    val values = mutableListOf(1, 2, 3)
    values.replaceAll { it + 1 }
    println(values)

    val calls = mutableListOf<Int>()
    val ordered = mutableListOf(3, 1, 2)
    ordered.replaceAll {
        calls.add(it)
        it * 10
    }
    println(calls)
    println(ordered)

    val empty = mutableListOf<Int>()
    var visited = 0
    empty.replaceAll {
        visited += 1
        it + 1
    }
    println("empty=$empty visited=$visited")

    ordered.add(1, 15)
    ordered[0] = 31
    println(ordered.removeAt(1))
    println(ordered)
}
