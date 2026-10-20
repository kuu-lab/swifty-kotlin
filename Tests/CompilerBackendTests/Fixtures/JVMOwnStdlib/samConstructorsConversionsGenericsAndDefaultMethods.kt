fun interface Op { fun apply(value: Int): Int; fun tag(): Int = 9 }
fun interface Transform<T> { fun apply(value: T): T }
fun use(op: Op): Int = op.apply(21)
fun main() {
    var offset = 1
    val op = Op { value -> value + offset }
    offset = 2
    println(op.apply(40))
    println(op.tag())
    println(use { it * 2 })
    val callback: (Int) -> Int = { it * 3 }
    println(use(callback))
    val transform = Transform<String> { it }
    println(transform.apply("sam"))
    val unit = Op { 7 }
    println(unit.apply(0))
}
