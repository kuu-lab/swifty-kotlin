fun apply(value: Int, operation: (Int) -> Int): Int = operation(value)
fun counter(start: Int): () -> Int { var current = start; return { current += 1; current } }
fun shared(): List<() -> Int> {
    var current = 0
    val next = { current += 1; current }
    val read = { current }
    return listOf(next, read)
}
fun main() {
    val scale = 3
    println(apply(14) { it * scale })
    val next = counter(8)
    println(next())
    println(next.invoke())
    val callbacks = shared()
    println(callbacks[0]())
    println(callbacks[1]())
    println(callbacks[0]())
    println(callbacks[1]())
    var outside = 10
    val change: (Int) -> Int = { n -> outside += n; outside }
    outside = 20
    println(change(22))
    println(outside)
    val nested: (Int) -> () -> Int = { x -> { x + scale } }
    println(nested(4)())
    val wide: (Long, Double) -> Double = { a, b -> a.toDouble() + b }
    println(wide(10L, 0.5))
}
