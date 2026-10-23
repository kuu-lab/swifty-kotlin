// KUU-2939: `toString()` must resolve and render correctly for implicit
// receivers of builtin types, `as T?`-boxed primitives, and generic
// `T.myToString()` receivers (JetBrains intrinsics/tostring.kt).

fun Any.extAny(): String = toString()
fun <T> T.extT(): String = toString()
fun <T : Any> T.extTA(): String = toString()
fun <T : Any> T.myToString(): String = toString()
fun <T : Any> T.myToStringThis(): String = this.toString()
fun Char.extC(): String = toString()
fun Boolean.extB(): String = toString()
fun Double.extD(): String = toString()
fun String.extS(): String = toString()

fun main() {
    // `as T?`-boxed primitives, string templates (JetBrains tostring.kt).
    println((239.toByte() as Byte?).toString())
    println((239.toShort() as Short?).toString())
    println((239.toInt() as Int?).toString())
    println((239.toFloat() as Float?).toString())
    println((239.toLong() as Long?).toString())
    println((239.toDouble() as Double?).toString())
    println((true as Boolean?).toString())
    println(('a'.toChar() as Char?).toString())
    println("${239.toByte()}" == (239.toByte() as Byte?).toString())

    // Implicit `toString()` on builtin/extension receivers.
    println("x".extS())
    println('c'.extC())
    println(true.extB())
    println(1.extT())
    println('c'.extT())
    println(true.extT())
    println(23.21.extD())
    println(23.21.extTA())

    // Generic `T.myToString()` — the receiver is boxed at the call site.
    println(23.21.myToString())
    println('c'.myToString())
    println(true.myToString())
    println(1.myToString())
    println("x".myToString())
    println('c'.myToStringThis())
    println(239.toByte().myToString())

    // Floating-point edge values through the generic path.
    println(Double.MIN_VALUE.myToString())
    println(Double.MAX_VALUE.myToString())
    println(Double.NEGATIVE_INFINITY.myToString())
    println(Double.POSITIVE_INFINITY.myToString())
    println(Float.MIN_VALUE.myToString())
    println(Float.MAX_VALUE.myToString())

    // Equality against the direct call keeps the renderings in lockstep.
    println(23.21.myToString() == 23.21.toString())
    println('c'.myToString() == 'c'.toString())
    println(true.myToString() == true.toString())

    // Every byte conversion value must survive the `as Byte?` boxing path.
    var byteMismatches = 0
    for (i in 0..255) {
        if (i.toByte().toString() != (i.toByte() as Byte?).toString()) byteMismatches++
    }
    println("byteMismatches=$byteMismatches")
}
