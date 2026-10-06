// KUU-1275: named vararg arguments supply arrays without an explicit spread.
fun h(vararg xs: Int, y: Int = 9): Int = xs.size + y
fun sumNamed(vararg xs: Int): Int = xs.sum()
fun words(vararg xs: String): String = xs.joinToString(",")
fun <T> countNamed(vararg xs: T): Int = xs.size
class NamedVararg(vararg xs: Int) {
    val total: Int = xs.sum()
    fun count(vararg xs: Int, y: Int = 3): Int = xs.size + y
}
open class NamedBase(vararg xs: Int) { val total: Int = xs.sum() }
class NamedChild(xs: IntArray): NamedBase(xs = xs)
object NamedObject: NamedBase(xs = intArrayOf(5, 6))
class NamedDelegation {
    val total: Int
    constructor(vararg xs: Int) { total = xs.sum() }
    constructor(xs: IntArray, marker: Boolean): this(xs = xs)
}
fun main() {
    println(h(xs = intArrayOf(5, 6)))
    println(h(*intArrayOf(5, 6)))
    println(h(1, 2))
    println(h(y = 4))
    println(h(y = 4, xs = intArrayOf(5, 6)))
    println(h(xs = intArrayOf()))
    println(h(xs = *intArrayOf(5, 6)))
    println(sumNamed(xs = intArrayOf(5, 6)))
    println(words(xs = arrayOf("a", "b")))
    println(countNamed(xs = arrayOf("a", "b")))
    println(countNamed(xs = arrayOf(5, 6)))
    val obj = NamedVararg(xs = intArrayOf(5, 6))
    println(obj.total)
    println(obj.count(xs = intArrayOf(5, 6)))
    val nullable: NamedVararg? = obj
    println(nullable?.count(xs = intArrayOf(5, 6)))
    println(NamedChild(intArrayOf(5, 6)).total)
    println(NamedDelegation(intArrayOf(5, 6), true).total)
    println(NamedObject.total)
    val anonymous = object: NamedBase(xs = intArrayOf(5, 6)) {}
    println(anonymous.total)
}
