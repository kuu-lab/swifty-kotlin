import klibvarargspread.*

private fun isIntArray(value: Any): Boolean = value is IntArray

fun main() {
    val ints = intArrayOf(2, 3)
    println(forward(ints))
    println(forward(intArrayOf()))

    val ordered = forwardInOrder(intArrayOf(20, 21), intArrayOf(40))
    println(evaluationOrder())
    println(ordered.contentToString())
    println(isIntArray(ordered))

    val copied = copySpread(ints)
    copied[0] = 99
    println(ints.contentToString())
    println(copied.contentToString())
    println(copySpread(intArrayOf()).size)

    val refs = forwardRefs(arrayOf(null, "left"), arrayOf("right"))
    println(refs.contentToString())
    println(refs[3] is Int)
    println(refs[5] is Char)
}
