inline fun <reified T : Any> checkReified(a: Array<*>): Boolean = a.isArrayOf<T>()

fun viaWith(a: Array<*>): Boolean = with(a) { isArrayOf<Int>() }

fun main() {
    val ints = arrayOf(1, 2)
    val nums: Array<Number> = arrayOf(1, 2)
    val anys: Array<Any> = arrayOf<Any>(1, "x")
    println(ints.isArrayOf<Int>())
    println(ints.isArrayOf<Number>())
    println(nums.isArrayOf<Number>())
    println(nums.isArrayOf<Int>())
    println(anys.isArrayOf<Any>())
    println(anys.isArrayOf<Int>())
    println(emptyArray<String>().isArrayOf<String>())
    println(emptyArray<String>().isArrayOf<Int>())
    val nested = arrayOf(ints, nums)
    println(nested.isArrayOf<Array<out Number>>())
    println(checkReified<Int>(ints))
    println(checkReified<String>(ints))
    println(checkReified<Number>(nums))
    println(viaWith(ints))
    println(viaWith(arrayOf("x")))
    val strs: Array<*> = arrayOf("a", "b")
    println(strs.isArrayOf<CharSequence>())
    println(strs.isArrayOf<String>())
    val maybeInts: Array<Int>? = ints
    val noInts: Array<Int>? = null
    println(maybeInts?.isArrayOf<Int>())
    println(noInts?.isArrayOf<Int>())
}
