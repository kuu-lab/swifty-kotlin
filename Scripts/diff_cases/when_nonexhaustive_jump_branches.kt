fun f(x: Int): String {
    when (x) { 1 -> return "one"; 2 -> throw IllegalStateException("two") }
    return "other"
}

fun g(x: Int): String {
    when { x == 1 -> return "one"; x == 2 -> throw IllegalStateException("two") }
    return "other"
}

fun main() {
    println(f(1))
    println(f(3))
    try { f(2) } catch (e: IllegalStateException) { println(e.message) }
    println(g(1))
    println(g(3))
    try { g(2) } catch (e: IllegalStateException) { println(e.message) }
    var k = 0
    loop@ while (true) {
        k++
        when { k % 2 == 0 -> continue@loop; k > 7 -> break@loop }
        print("$k ")
    }
    println()
    for (i in 1..5) { when (i) { 2 -> continue; 4 -> break }; print(i) }
    println()
}
