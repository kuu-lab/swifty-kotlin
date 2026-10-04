fun main() {
    // Long: static type
    println((1L shl 40).hashCode())
    println((-5L).hashCode())
    println(0L.hashCode())
    println(Long.MAX_VALUE.hashCode())
    println((-1L).hashCode())

    // Long: Any-erased (always boxed, so these also exercise the boxed path
    // for a value whose raw bit pattern equals the runtime's null sentinel)
    val anyLong1: Any = 1L shl 40
    println(anyLong1.hashCode())
    val anyLong2: Any = -5L
    println(anyLong2.hashCode())
    val anyLong3: Any = Long.MIN_VALUE
    println(anyLong3.hashCode())

    // Float: static type
    println((-2.5f).hashCode())
    println(0.0f.hashCode())
    println((-0.0f).hashCode())
    println(Float.NaN.hashCode())

    // Float: Any-erased
    val anyFloat1: Any = -2.5f
    println(anyFloat1.hashCode())
    val anyFloat2: Any = Float.NaN
    println(anyFloat2.hashCode())

    // Double: static type
    println(1.5.hashCode())
    println(0.0.hashCode())
    println(Double.NaN.hashCode())
    println((-2.5).hashCode())

    // Double: Any-erased
    val anyDouble1: Any = 1.5
    println(anyDouble1.hashCode())
    val anyDouble2: Any = Double.NaN
    println(anyDouble2.hashCode())

    // ULong: static type
    val u1: ULong = 1UL shl 40
    println(u1.hashCode())
    val u2: ULong = ULong.MAX_VALUE
    println(u2.hashCode())

    // ULong: Any-erased
    val anyULong1: Any = u1
    println(anyULong1.hashCode())
    val anyULong2: Any = 9223372036854775808UL // 2^63
    println(anyULong2.hashCode())

    // List/Set/Map.hashCode() compose per-element hashCode()s, so they also
    // exercise the boxed Long/Float/Double path above. The 10-element list
    // is long enough that Kotlin's 32-bit-wrapping fold(1) { 31*acc+e.hashCode() }
    // diverges from a naive 64-bit accumulation, stressing that the fix
    // wraps at 32 bits on every step, not just once at the end.
    println(listOf(1L shl 40).hashCode())
    println(setOf(-2.5f, 1.5).hashCode())
    println(mapOf("k" to (1L shl 40)).hashCode())
    println(listOf(1, 2, 3, 4, 5, 6, 7, 8, 9, 10).hashCode())
    println(setOf(1, 2, 3, 4, 5, 6, 7, 8, 9, 10).hashCode())
}
