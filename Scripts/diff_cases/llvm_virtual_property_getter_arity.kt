abstract class Base {
    abstract val size: Int
    abstract fun get(index: Int): Int
}

class Impl : Base() {
    override val size: Int = 3
    override fun get(index: Int): Int = index * 10
}

fun probe(b: Base): Int {
    var sum = 0
    for (i in 0 until b.size) {
        sum += b.get(i)
    }
    return sum
}

fun main() {
    println(probe(Impl()))
}
