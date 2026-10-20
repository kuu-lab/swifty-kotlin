inline fun twice(value: Int, block: (Int) -> Int): Int = block(value) + block(value)
inline fun guarded(block: () -> Int): Int {
    try { return block() } finally { println("guard") }
}
inline fun <T> T.pipe(block: (T) -> T): T = block(this)
inline fun save(noinline block: () -> Int): () -> Int = block
inline fun wrap(crossinline block: () -> Int): () -> Int = { block() }
fun early(): Int { guarded { return 42 }; return 0 }
fun local(): Int = guarded { if (true) return@guarded 7; 0 }
fun main() {
    var calls = 0
    println(twice(10) { calls += 1; it + calls })
    println(calls)
    println(early())
    println(local())
    println(21.pipe { it * 2 })
    println(save { 8 }())
    println(wrap { 9 }())
}
