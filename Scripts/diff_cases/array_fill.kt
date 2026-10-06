// Regression for KUU-554: Array/IntArray/BooleanArray.fill resolves to
// kk_array_fill, which must write through the O(1) slot subscript and keep
// each slot's anyFallbackTag instead of rebuilding storage per element.
fun main() {
    val boxed = arrayOf(1, 2, 3, 4)
    boxed.fill(9)
    println(boxed.toList())

    val ints = IntArray(4)
    ints.fill(7)
    println(ints.toList())

    val bools = BooleanArray(3)
    bools.fill(true)
    println(bools.toList())

    val strings = arrayOf("a", "b")
    strings.fill("z")
    println(strings.toList())

    val anys: Array<Any> = arrayOf(1L, "x", 2.5)
    anys.fill(4L)
    println(anys.toList())
}
