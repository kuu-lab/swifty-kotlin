// Java's FloatingDecimal does not emit the globally shortest round-tripping
// decimal: when a length-1 decimal round-trips (p = 1), it selects the
// closest decimal to the exact value among all length-1-or-2 candidates.
// Ryu's 1-digit answers (`3e-45`, `1e-323`) must become `2.8E-45`, `9.9E-324`.
fun main() {
    for (b in 1..12) println(Float.fromBits(b))
    for (b in 1L..12L) println(Double.fromBits(b))
    println(Double.fromBits(64L))
    println(Double.fromBits(255L))
    println(Float.fromBits(0x00400000))
    println(-2.8e-45f)
    println(-9.9e-324)
    println(1.4e-45f + 1.4e-45f)
    println(4.9e-324 * 2)
    println("cf:" + 2.8e-45f)
    println("cf:" + 9.9e-324)
    println(2.8e-45f.toString())
    println((9.9e-324).toString())
    // Nearby normals and boundary values must keep their Ryu form.
    println(Float.fromBits(0x007FFFFF))
    println(0.5f)
    println(0.5)
    println(1e7)
}
