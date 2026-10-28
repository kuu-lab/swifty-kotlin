// KUU-3603: kotlin.UInt and kotlin.ULong implement Comparable<Self>, so the
// member call, the Comparable<T> constraint, and Comparable-driven stdlib
// functions must all resolve. Ordering is unsigned (UInt.MAX_VALUE > 0u).

val ua = 1234U
val ub = 5678U

fun <T : Comparable<T>> maxOfT(a: T, b: T): T = if (a.compareTo(b) >= 0) a else b

fun main() {
    // Literal receivers, both directions plus equality.
    println(1u.compareTo(2u))
    println(2u.compareTo(1u))
    println(1u.compareTo(1u))
    println(1uL.compareTo(2uL))
    println(2uL.compareTo(1uL))
    println(1uL.compareTo(1uL))

    // Inferred-unsigned receivers (JetBrains unsignedIntCompare shape).
    println(ua.compareTo(ub))
    println(ub.compareTo(ua))
    println(ua.compareTo(ua) == 0)

    // Unsigned overflow ordering: max values sort above small ones.
    println(0u.compareTo(UInt.MAX_VALUE))
    println(UInt.MAX_VALUE.compareTo(0u))
    println(0uL.compareTo(ULong.MAX_VALUE))
    println(ULong.MAX_VALUE.compareTo(0uL))

    // Comparable<UInt>/Comparable<ULong> constraints.
    val cu: Comparable<UInt> = 1u
    println(cu.compareTo(2u))
    val cul: Comparable<ULong> = 1uL
    println(cul.compareTo(2uL))
    println(maxOfT(1u, 2u))
    println(maxOfT(2uL, 1uL))

    // Cross-width member overloads and literal coercion.
    println(1u.compareTo(2uL))
    println(1uL.compareTo(2u))
    println(1u.compareTo(1u.toUByte()))
    println(1u.compareTo(1u.toUShort()))

    // Comparable-driven stdlib functions on unsigned elements.
    println(listOf(3u, 1u, 2u).sorted())
    println(listOf(3uL, 1uL, 2uL).sorted())
    println(listOf(3u, 1u, 2u).max())
    println(listOf(3u, 1u, 2u).min())
    println(listOf(3uL, 1uL, 2uL).max())
    println(listOf(3uL, 1uL, 2uL).min())
    println(maxOf(1u, 2u))
    println(minOf(1u, 2u))
    println(maxOf(1uL, 2uL))
    println(minOf(1uL, 2uL))

    // Equality alongside ordering.
    println(1u == 1u)
    println(1u != 2u)
    println(1uL == 1uL)
    println(1uL != 2uL)
}
