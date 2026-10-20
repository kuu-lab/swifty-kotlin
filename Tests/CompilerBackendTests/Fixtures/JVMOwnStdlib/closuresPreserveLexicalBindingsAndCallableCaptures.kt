fun later(callback: (Int) -> Int): () -> Int = { callback(21) }
fun main() {
    val outer = 7
    val read = { outer }
    println(({ val outer = 100; read() + outer })())
    val typed = { left: Int, right: Int -> left + right }
    val callback = later { typed(it, it) }
    println(callback())
    var operation: ((Int) -> Int)? = null
    val replace = { operation = { it * 2 } }
    replace()
    println(operation!!(21))
    val callbacks = mutableListOf<() -> Int>()
    for (i in 1..3) {
        var value = i
        callbacks.add { value += 10; value }
    }
    println(callbacks[0]())
    println(callbacks[1]())
    println(callbacks[0]())
    val wide = 20L
    val decimal = 0.5
    println(({ wide + decimal })())
}
