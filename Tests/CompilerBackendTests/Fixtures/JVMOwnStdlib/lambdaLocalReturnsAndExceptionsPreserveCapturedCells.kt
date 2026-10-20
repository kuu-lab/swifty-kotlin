fun operate(block: (Int) -> Int): Int = block(2)
fun main() {
    var total = 0
    val change: (Int) -> Int = action@ { n ->
        try {
            total += n
            if (n < 0) throw IllegalStateException("negative")
            if (n == 0) return@action total
            total
        } finally { println("finally") }
    }
    println(change(3))
    try { change(-1) } catch(e: IllegalStateException) { println(e.message) }
    println(change(0))
    println(operate { value -> if (value == 2) return@operate 42; 0 })
    var index = 0
    val callbacks = mutableListOf<() -> Int>()
    for (i in 1..3) { callbacks.add { i } }
    while (index < callbacks.size) { println(callbacks[index]()); index++ }
}
