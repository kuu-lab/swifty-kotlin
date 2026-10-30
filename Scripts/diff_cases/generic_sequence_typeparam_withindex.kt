// KUU-3202: an unresolved `withIndex` on a `T : Sequence` receiver must reach
// the kk_sequence_* runtime family (previously it emitted a bare `withIndex`
// extern that never linked), and the IndexedValue elements it yields must
// support compiled member reads and destructuring.
fun <T : Sequence<*>> indexed(sequence: T): String {
    val s = StringBuilder()
    for ((index, x) in sequence.withIndex()) {
        s.append("$index:$x;")
    }
    return s.toString()
}

fun <T : Sequence<String>> described(sequence: T): String {
    val s = StringBuilder()
    for (iv in sequence.withIndex()) {
        s.append("${iv.index}=${iv.value};")
    }
    return s.toString()
}

fun <T : Sequence<Int>> counted(sequence: T): Int {
    var count = 0
    for (iv in sequence.withIndex()) {
        count += iv.index
    }
    return count
}

fun main() {
    println(indexed(listOf("a", "b", "c", "d").asSequence()))
    println(described(listOf("x", "y").asSequence()))
    println(counted(listOf(7, 8, 9).asSequence()))
}
