package diff

private fun <T> Array<T>.implicitSize(): Int = size
private fun IntArray.implicitSize(): Int = size

fun main() {
    val source = arrayOf(3, 1, 2)
    println(source.plus(4).toList())
    println(source.plus(arrayOf(4, 5)).toList())
    println(source.plus(listOf(4, 5)).toList())
    println(source.plusElement(4).toList())
    println((arrayOf(1) + 2).toList())
    println(source.toList())

    val ints = intArrayOf(3, 1, 2)
    println(ints.sorted())
    println(ints.plus(4).toList())
    println(ints.plus(intArrayOf(4, 5)).toList())
    println(ints.plus(listOf(4, 5)).toList())
    println(ints.toList())
    println(source.implicitSize())
    println(ints.implicitSize())
}
