interface Box<T> {
    fun get(): T
}

abstract class AbstractBox<T> : Box<T> {
    abstract fun compute(): T
    override fun get(): T = compute()
}

class IntBox(val v: Int) : AbstractBox<Int>() {
    override fun compute(): Int = v
}

class DoubledBox(val v: Int) : AbstractBox<Int>() {
    override fun compute(): Int = v * 2
}

fun accept(b: Box<Int>): Int = b.get()

fun main() {
    val box = IntBox(7)
    println(box.compute())
    println(box.get())
    println(accept(box))
    println(accept(DoubledBox(7)))
    val boxes: List<Box<Int>> = listOf(IntBox(1), DoubledBox(1))
    for (b in boxes) {
        println(b.get())
    }
}
