data class Arrays(val ints: IntArray, val strings: Array<String>)
data class NullableArrays(val ints: IntArray?, val strings: Array<String>?)

fun main() {
    val value = Arrays(intArrayOf(1, 2), arrayOf("x"))
    println(value.toString())
    println(value)
    println(NullableArrays(null, null))
    println(Arrays(intArrayOf(1, 2), arrayOf("x")) == value)
}
