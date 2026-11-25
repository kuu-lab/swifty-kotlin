// DIFF_JVM
// Float/Double.toRawBits()/toBits() are @InlineOnly in kotlin-stdlib; the JVM
// backend must lower them to java.lang.Float/Double bit intrinsics so consumer
// sources (e.g. Compose ui-geometry) resolve them under --emit jar. The lowering
// must hold for explicit calls and for implicit-receiver calls inside extension
// bodies, while user-defined extensions still resolve normally.
// (Aliased-import coverage lives in float_double_to_bits_alias.kt: an explicit
// aliased import captures the kotlin.* star-import name, so kotlinc rejects
// mixing alias imports with plain toBits/toRawBits calls in one file.)
fun Double.implicitToBits(): Long = toBits()
fun Double.implicitToRawBits(): Long = toRawBits()
fun Float.implicitToBitsF(): Int = toBits()
fun Float.implicitToRawBitsF(): Int = toRawBits()

fun Float.userToBits(): Int = 999

fun main() {
    val f = 1.5f
    println(f.toRawBits())
    println(f.toBits())
    println((-2.0f).toRawBits())
    println(0.0f.toBits())
    println((-0.0f).toBits())
    println(Float.NaN.toBits())
    println(Float.POSITIVE_INFINITY.toRawBits())
    println(Float.NEGATIVE_INFINITY.toRawBits())

    val d = 1.5
    println(d.toRawBits())
    println(d.toBits())
    println((-2.0).toRawBits())
    println(0.0.toBits())
    println((-0.0).toBits())
    println(Double.NaN.toBits())
    println(Double.POSITIVE_INFINITY.toRawBits())
    println(Double.NEGATIVE_INFINITY.toRawBits())

    // Implicit-receiver calls inside extension bodies.
    println(d.implicitToBits())
    println(d.implicitToRawBits())
    println(f.implicitToBitsF())
    println(f.implicitToRawBitsF())

    // A user-defined extension is not hijacked by the stdlib lowering.
    println(f.userToBits())
}
