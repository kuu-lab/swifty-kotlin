// DIFF_JVM
// Float/Double.toRawBits()/toBits() are @InlineOnly in kotlin-stdlib; the JVM
// backend must lower them to java.lang.Float/Double bit intrinsics so consumer
// sources (e.g. Compose ui-geometry) resolve them under --emit jar.
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
}
