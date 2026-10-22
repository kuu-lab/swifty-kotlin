inline fun consume(block: (Int) -> Int): Int { block(1); return 99 }
fun outer(): Int {
    val result = consume(fun(x: Int): Int { return x + 1 })
    return result
}
fun main() {
    val triple = fun(x: Int): Int { if (x < 0) return 0; return x * 3 }
    println(triple(2)); println(triple(-2))
    val offset = 10
    val capture = fun(x: Int): Int = x + offset
    println(capture(5))
    val receiver = fun Int.(): String { return "OK" }
    println(1.receiver())
    println(outer())
}
