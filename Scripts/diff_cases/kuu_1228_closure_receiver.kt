class Counter(var value: Int) {
    fun step(): Int { value += 1; return value }
    fun run(): Int {
        val bump: (Int) -> Unit = { step() }
        bump(0)
        return value
    }
}

class Box {
    fun plus(x: Int): Int = x
}

fun boundCall(box: Box): Int {
    val f = box::plus
    return f(7)
}

class OffsetBox(val offset: Int) {
    fun plus(x: Int): Int = offset + x
}

fun main() {
    val first = Counter(10)
    val second = Counter(20)
    println(first.run())
    println(second.run())
    println(first.run())
    println(boundCall(Box()))
    val left = OffsetBox(30)::plus
    val right = OffsetBox(40)::plus
    println(left(7))
    println(right(8))
    println(left(9))
}
