// KUU-2852: boxed floating-point equality treats NaN payload variants as equal.
fun main() {
    val a = Double.NaN
    val b = Double.fromBits(0xFFF80000L shl 32)
    println(a.compareTo(b))
    println(a.equals(b))
    val ba: Any = a
    val bb: Any = b
    println(ba == bb)
    println(bb.equals(ba))

    val payload = Double.fromBits(0x7FF8000000000001L)
    val payloadBox: Any = payload
    println(ba == payloadBox)

    val floatA = Float.fromBits(0x7FC00001)
    val floatB = Float.fromBits(Int.MIN_VALUE + 0x7FC00042)
    val floatBoxA: Any = floatA
    val floatBoxB: Any = floatB
    println(floatA.equals(floatB))
    println(floatBoxA == floatBoxB)

    println(a == b)
    println((-0.0).equals(0.0))
    val negativeZero: Any = -0.0
    val positiveZero: Any = 0.0
    println(negativeZero == positiveZero)
}
