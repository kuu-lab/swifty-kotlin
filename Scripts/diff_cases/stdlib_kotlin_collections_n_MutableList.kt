// KSP-944: source-backed MutableList shell and initializer factory.
fun main() {
    var calls = 0
    val values = MutableList(4) { index ->
        calls++
        index * 2
    }

    println(values)
    println("calls=$calls")

    values[1] = 99
    values.add(2, 7)
    val removed = values.removeAt(0)
    val throughInterface: MutableList<Int> = values
    println("removed=$removed values=$throughInterface")
    println("indexed=${throughInterface[1]} size=${throughInterface.size}")

    try {
        MutableList(-1) {
            calls += 100
            it
        }
        println("negative-not-thrown")
    } catch (e: IllegalArgumentException) {
        println("negative=${e.message}")
    }
    println("calls=$calls")

    val empty = MutableList(0) {
        calls += 1000
        it
    }
    println("empty=$empty calls=$calls")
}
