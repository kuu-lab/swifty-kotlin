// SPEC-NUM-0008: Double/Float member calls on negative zero.
// Verifies: toString() on -0.0/-0.0f, compareTo on Float, and -0.0 return-value sign.
fun negZeroDouble(): Double = -0.0
fun negZeroFloat(): Float = -0.0f

fun main() {
    // toString() must not return "null" (null-sentinel collision with -0.0 bit pattern)
    println((-0.0).toString())
    println((-0.0f).toString())
    val d: Double = -0.0
    println(d.toString())
    val f: Float = -0.0f
    println(f.toString())

    // Return-value path must preserve sign
    println(negZeroDouble())
    println(negZeroFloat())

    // Float.compareTo must not produce a link error
    println(2.5f.compareTo(1.5f))
    println(1.5f.compareTo(2.5f))
    println(1.5f.compareTo(1.5f))
}
