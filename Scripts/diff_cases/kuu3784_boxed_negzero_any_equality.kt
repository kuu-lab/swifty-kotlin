// KUU-3784: a boxed -0.0 stored in Any must equal an identical -0.0 under
// `==` and `.equals` (JVM: true). Non-const top-level vals fold their
// literal initializer into read sites; the raw -0.0 bits are the runtime
// null sentinel, so a folded read mis-compared as null. Long.MIN_VALUE,
// ULong 2^63 and -0.0f collide with the sentinel the same way.
val topAny: Any = -0.0
val topAnyLong: Any = Long.MIN_VALUE
val topAnyULong: Any = 0x8000000000000000uL
val topAnyFloat: Any = -0.0f
val topAnyInt: Any = 5
val topNullableDouble: Double? = -0.0
val topNullableLong: Long? = Long.MIN_VALUE
val topNullableFloat: Float? = -0.0f
val topPlainDouble: Double = -0.0

fun main() {
    // The reported divergence (top-level `val x: Any = -0.0`).
    println(topAny == -0.0)
    println(topAny.equals(-0.0))
    println(topAny == 0.0)
    println(topAny.equals(0.0))
    println(topAny == null)
    println(topAny.hashCode())

    // The local form already behaved; keep it pinned.
    val localAny: Any = -0.0
    println(localAny == -0.0)
    println(localAny.equals(-0.0))
    println(localAny == topAny)

    // Other sentinel-colliding payloads in Any slots.
    println(topAnyLong == Long.MIN_VALUE)
    println(topAnyLong.equals(Long.MIN_VALUE))
    println(topAnyULong == 0x8000000000000000uL)
    println(topAnyFloat == -0.0f)
    println(topAnyFloat.equals(-0.0f))
    println(topAnyInt == 5)
    println(topAnyInt.equals(5))

    // Nullable sentinel-colliding vals must not fold to a raw word that
    // reads as null.
    println(topNullableDouble == -0.0)
    println(topNullableDouble == null)
    println(topNullableDouble != null)
    println(topNullableDouble?.equals(-0.0))
    println(topNullableLong == Long.MIN_VALUE)
    println(topNullableLong == null)
    println(topNullableFloat == -0.0f)
    println(topNullableFloat == null)

    // Nullable primitives whose values cannot collide keep folding safely.
    val nullableInt: Int? = 5
    println(nullableInt == 5)
    println(nullableInt == null)

    // `==` stays IEEE for primitive operands; boxed equality keeps its
    // signed-zero/NaN distinctions.
    val nanAny: Any = Double.NaN
    println(nanAny.equals(Double.NaN))
    println(nanAny == Double.NaN)
    println(topAnyInt == 5L)
    println(listOf(topAny).contains(-0.0))
    println(-0.0 == 0.0)
    println((-0.0).equals(0.0))
    println(topPlainDouble == -0.0)
}
