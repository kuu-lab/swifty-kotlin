// DIFF_JVM
class Singleton : AbstractList<Int>() {
    override val size: Int get() = 1
    override fun get(index: Int): Int = 42
}

fun main() { println(Singleton()[0]) }
