fun describe(value: Any?): String = when (value) {
    is Byte -> "Byte:$value"
    is Short -> "Short:$value"
    is Int -> "Int:$value"
    else -> "Other:$value"
}

fun main() {
    val bytes = arrayOf<Byte>(1, 2, -128, +127)
    val shorts = arrayOf<Short>(1, 2, -32768, +32767)
    println(bytes.joinToString())
    println(shorts.joinToString())
    println(describe(bytes[0]))
    println(describe(bytes[2]))
    println(describe(bytes[3]))
    println(describe(shorts[0]))
    println(describe(shorts[2]))
    println(describe(shorts[3]))
    println(describe(arrayOf<Byte?>(3, null)[0]))
    println(describe(arrayOf(4, 5)[0]))
}
