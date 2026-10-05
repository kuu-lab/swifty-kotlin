// KUU-1274: Local vararg bodies must use the same parameter types as top-level functions.
fun sinkInts(xs: IntArray): Int = xs.size

fun main() {
    fun block(vararg xs: Int) {
        val array: IntArray = xs
        println(xs.sum())
        println(xs.size)
        println(xs.first())
        println(sinkInts(array))
        println(xs[0])
        for (x in xs) println(x)
    }
    fun expression(vararg xs: Int) = xs.sum()
    fun strings(vararg xs: String): Int = xs.size
    fun ordinary(xs: IntArray): Int = xs.sum()

    block(1, 2, 3)
    block(*intArrayOf(4, 5))
    println(expression(6, 7))
    println(strings("a", "b"))
    println(ordinary(intArrayOf(8, 9)))
}
