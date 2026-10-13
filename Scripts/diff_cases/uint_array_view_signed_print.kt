// KUU-1937: UIntArray views retain signed storage but render unsigned elements.
@OptIn(ExperimentalUnsignedTypes::class)
fun main() {
    val view = intArrayOf(-1, 4).asUIntArray()
    println("view=${view.joinToString()}")
    println("elem=${view[0]}")
    println("elemToInt=${view[0].toInt()}")
    println("elemPlus=${view[0] + 0u}")
    val copied = intArrayOf(-1, 4).toUIntArray()
    println("copy=${copied.joinToString()}")
    println("copyElem=${copied[0]}")

    val signed = intArrayOf(-1, -2147483648, 0, 2147483647)
    val unsigned = signed.asUIntArray()
    println(unsigned.joinToString())
    println(unsigned.joinToString(";") { it.toString() })
    println(unsigned[0])
    println(unsigned[1].toString())
    val erased: Any = unsigned[0]
    val nullable: UInt? = unsigned[1]
    println(erased)
    println(nullable)
    println(listOf(unsigned[0], unsigned[1]))
    println(unsigned.toList())
    println(unsigned[0].hashCode())
    println(unsigned[1].hashCode())
    signed[0] = -2
    println(unsigned[0].toString())
    unsigned[1] = 7u
    println(signed.joinToString())
    println(unsigned.joinToString())
    println(longArrayOf(-1L).asULongArray().joinToString())
}
