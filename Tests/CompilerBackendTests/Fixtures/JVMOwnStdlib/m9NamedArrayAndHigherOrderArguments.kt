fun mark(n: Int): Int { println(n); return n }
fun initializer(): (Int) -> Int { println("init"); return { it + 1 } }
fun operation(): (Int, Int) -> Int { println("operation"); return { a, b -> a + b } }
fun main() {
    val values = IntArray(init = initializer(), size = mark(3))
    println(message = values.fold(operation = operation(), initial = mark(10)))
    println(values.map(transform = { it * 2 })[2])
}
