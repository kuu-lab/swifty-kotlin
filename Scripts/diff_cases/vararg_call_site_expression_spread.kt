// KUU-1589: expression spreads, named vararg arrays, and source-order evaluation.
var events = ""

fun markInt(label: String, value: Int): Int {
    events += label
    return value
}

fun markInts(label: String, value: IntArray): IntArray {
    events += label
    return value
}

fun markString(label: String, value: String): String {
    events += label
    return value
}

fun markArray(label: String, value: IntArray): IntArray {
    events += label
    return value
}

fun ints(): IntArray = intArrayOf(2)
fun strings(): Array<String> = arrayOf("a", "b")

fun g(vararg xs: Int) = xs.toList().toString()
fun v(vararg xs: String) = xs.toList().toString()
fun h(s: String, vararg xs: Int, t: Int = 0) = "$s/${xs.toList()}/$t"

fun main() {
    println(g(*intArrayOf(1, 2)))
    println(g(1, *intArrayOf(2), 3))
    println(g(*ints()))
    println(v(*arrayOf("a", "b")))
    println(v(*strings()))
    println(h("s", t = 5))
    println(h("s", 1, 2, t = 5))
    println(h("s", xs = intArrayOf(7), t = 1))

    events = ""
    println(g(markInt("a", 1), *markInts("b", intArrayOf(2)), markInt("c", 3)))
    println(events)

    events = ""
    println(h(markString("s", "s"), t = markInt("t", 4), xs = markArray("x", intArrayOf(7))))
    println(events)
}
