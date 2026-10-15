import java.util.Arrays.hashCode

fun main() {
    println(java.util.Arrays.hashCode(intArrayOf()))
    println(hashCode(intArrayOf()))
    println(java.util.Arrays.hashCode(intArrayOf(1)))
    println(hashCode(intArrayOf(1)))
    println(java.util.Arrays.hashCode(intArrayOf(1, 2, 3)))
    println(hashCode(intArrayOf(1, 2, 3)))
    println(java.util.Arrays.hashCode(intArrayOf(-1, 2, -1)))
    println(hashCode(intArrayOf(-1, 2, -1)))

    val nullable: IntArray? = null
    println(java.util.Arrays.hashCode(nullable))
    println(hashCode(nullable))

    val bytes = byteArrayOf(1, 2, 3)
    java.util.Arrays.fill(bytes, (-7).toByte())
    check(bytes.contentEquals(byteArrayOf(-7, -7, -7)))
    println("fill:OK")
}
