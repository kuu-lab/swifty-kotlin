// KUU-4446: an integer literal stored through an unchecked Array<Any?> view
// keeps the generic array's primitive element context on the JVM.
inline fun tryStore(label: String, block: () -> Unit) {
    try {
        block()
        println("$label: stored")
    } catch (e: Exception) {
        println("$label: ${e::class.simpleName}")
    }
}

fun widen(values: Array<Long>): Array<Any?> = values as Array<Any?>

fun main() {
    val bytes = arrayOf<Byte>(1)
    val originalBytes = bytes
    (bytes as Array<Any?>)[0] = 7
    println("byte:${originalBytes[0]}")

    val shorts = arrayOf<Short>(1)
    val originalShorts = shorts
    (shorts as Array<Any?>)[0] = 7
    println("short:${originalShorts[0]}")

    val ints = arrayOf(1)
    val originalInts = ints
    (ints as Array<Any?>)[0] = 7
    println("int:${originalInts[0]}")

    val longs = arrayOf(1L)
    val originalLongs = longs
    (longs as Array<Any?>)[0] = 7
    println("long:${originalLongs[0]}")

    val floats = arrayOf(1.0f)
    tryStore("float") { (floats as Array<Any?>)[0] = 7 }

    val doubles = arrayOf(1.0)
    tryStore("double") { (doubles as Array<Any?>)[0] = 7 }

    tryStore("boundary") { widen(originalLongs)[0] = 7 }
}
