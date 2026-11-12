// DIFF_JVM
// Verifies Java overloads for trailing and interleaved defaults while preserving Kotlin defaults.

class Box {
    @JvmOverloads fun value(a: Int = 40, b: Int = 2): Int = a + b
    @JvmOverloads fun boundary(a: Int = 10, required: Int, tail: Int = 3): Int = a + required + tail
    fun ordinary(a: Int = 40, b: Int = 2): Int = a + b
}

fun main() {
    val box = Box()
    println(box.value())
    println(box.value(40))
    println(box.value(40, 2))
    println(box.ordinary())
    println(box.boundary(required = 5))
}
