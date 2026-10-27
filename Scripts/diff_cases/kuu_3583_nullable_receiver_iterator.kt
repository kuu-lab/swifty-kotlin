// KUU-3583: for-in desugars `iterator()` through the ordinary extension
// candidate path, so a `T?.iterator()` extension must bind for a non-null
// concrete receiver (here `Int`), matching JetBrains testData
// codegen/box/functions/kt1199.kt.

interface MyIterator<T> {
    operator fun hasNext(): Boolean
    operator fun next(): T
}

class RepeatIterator<T>(private val value: T, private val times: Int) : MyIterator<T> {
    private var count = 0
    override fun hasNext(): Boolean = count < times
    override fun next(): T {
        count += 1
        return value
    }
}

operator fun <T : Any> T?.iterator(): MyIterator<T> = RepeatIterator(this as T, 2)

fun <T : Any> T?.describe(): String = "ext:${this}"

fun main() {
    for (i in 1) println(i)
    println((7).describe())
    val maybe: Long? = null
    println(maybe.describe())
}
