import kotlin.collections.AbstractIterator

class OneShot(private val v: Int) : AbstractIterator<Int>() {
    private var used = false
    override fun computeNext() {
        if (used) done() else { used = true; setNext(v) }
    }
}

abstract class Counter {
    var count: Int = 10
    fun bump(): Unit = step()
    protected abstract fun step(): Unit
}

class ByTwo : Counter() {
    override fun step() {
        count = count + 2
    }
}

open class BaseWithArguments(val value: Int, val offset: Int) {
    val adjusted: Int = value * 2 + offset
}

class DerivedWithArguments(
    val source: Int,
    val delta: Int
) : BaseWithArguments(source, delta)

fun main() {
    val it = OneShot(42)
    while (it.hasNext()) println(it.next())
    val c = ByTwo()
    println(c.count)
    c.bump()
    println(c.count)
    println(DerivedWithArguments(3, 1).adjusted)
}
