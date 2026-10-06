// KUU-937: bare array size must match explicit this.size in extension receivers.
fun CharArray.bareSize(): Int = size
fun CharArray.explicitSize(): Int = this.size
fun IntArray.bareSize(): Int = size
fun IntArray.explicitSize(): Int = this.size
fun IntArray.localSize(): Int {
    val size = 41
    return size
}
fun String.bareLength(): Int = length

class SizeHolder(val size: Int) {
    fun bareSize(): Int = size
}

fun main() {
    val chars = charArrayOf('a', 'b', 'c', 'd')
    val ints = intArrayOf(2, 4, 6)
    println("${chars.bareSize()}:${chars.explicitSize()}")
    println("${ints.bareSize()}:${ints.explicitSize()}")
    println("${charArrayOf().bareSize()}:${intArrayOf().bareSize()}")
    println("${"abc".bareLength()}:${SizeHolder(27).bareSize()}")
    println(ints.localSize())
}
