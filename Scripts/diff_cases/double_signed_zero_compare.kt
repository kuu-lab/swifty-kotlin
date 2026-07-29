fun main() {
    println((-0.0).compareTo(0.0))
    println((0.0).compareTo(-0.0))
    println((0.0).compareTo(0.0))
    println((-0.0).compareTo(-0.0))
    println((-0.0f).compareTo(0.0f))
    println((0.0f).compareTo(-0.0f))

    val negZero = -0.0
    val posZero = 0.0
    println(negZero.compareTo(posZero))
    println(posZero.compareTo(negZero))
    println(negZero == posZero)

    println(doubleArrayOf(0.0, -0.0, 1.0, -1.0).sortedArray().joinToString(","))
    println(floatArrayOf(0.0f, -0.0f, 1.0f, -1.0f).sortedArray().joinToString(","))
}
