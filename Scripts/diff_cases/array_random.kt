import kotlin.random.Random

// KUU-1392: random()/randomOrNull() on generic, primitive, and unsigned arrays.
// Seeded Random(n) picks are XorWow-parity-locked vs JVM (see
// random_xorwow_parity.kt), so seeded println values byte-compare; unseeded
// calls assert membership/contract booleans only.
// Note: kotlin-stdlib has no Map.random overloads — map.entries is the
// upstream path — so Map receivers are intentionally not exercised here.

@OptIn(ExperimentalUnsignedTypes::class)
private fun unsignedArrays() {
    val uInt = uintArrayOf(10u, 20u, 30u)
    println(uInt.random(Random(42)))
    println(uInt.toList().contains(uInt.random()))
    println(uInt.randomOrNull(Random(7)))
    println(uInt.randomOrNull() != null)
    println(uintArrayOf().randomOrNull())
    try {
        uintArrayOf().random()
        println(false)
    } catch (e: NoSuchElementException) {
        println(e.message)
    }

    val uLong = ulongArrayOf(4uL, 5uL, 6uL)
    println(uLong.random(Random(42)))
    println(uLong.toList().contains(uLong.random()))
    println(uLong.randomOrNull(Random(8)))
    println(uLong.randomOrNull() != null)
    println(ulongArrayOf().randomOrNull())

    val uByte = ubyteArrayOf(9u, 10u)
    println(uByte.random(Random(42)))
    println(uByte.toList().contains(uByte.random()))
    println(uByte.randomOrNull(Random(9)))
    println(uByte.randomOrNull() != null)
    println(ubyteArrayOf().randomOrNull())

    val uShort = ushortArrayOf(11u, 12u)
    println(uShort.random(Random(42)))
    println(uShort.toList().contains(uShort.random()))
    println(uShort.randomOrNull(Random(10)))
    println(uShort.randomOrNull() != null)
    println(ushortArrayOf().randomOrNull())
}

fun main() {
    val ints = intArrayOf(10, 20, 30)
    println(ints.random(Random(42)))
    println(ints.toList().contains(ints.random()))
    println(ints.randomOrNull(Random(1)))
    println(ints.randomOrNull() != null)
    println(intArrayOf().randomOrNull())
    try {
        intArrayOf().random()
        println(false)
    } catch (e: NoSuchElementException) {
        println(e.message)
    }

    val longs = longArrayOf(1L, 2L, 3L)
    println(longs.random(Random(42)))
    println(longs.toList().contains(longs.random()))
    println(longs.randomOrNull(Random(2)))
    println(longs.randomOrNull() != null)

    val bytes = byteArrayOf(5, 6, 7)
    println(bytes.random(Random(42)))
    println(bytes.toList().contains(bytes.random()))
    println(bytes.randomOrNull(Random(3)))
    println(bytes.randomOrNull() != null)

    val shorts = shortArrayOf(8, 9)
    println(shorts.random(Random(42)))
    println(shorts.toList().contains(shorts.random()))
    println(shorts.randomOrNull(Random(4)))
    println(shorts.randomOrNull() != null)

    val chars = charArrayOf('a', 'b', 'c')
    println(chars.random(Random(42)))
    println(chars.toList().contains(chars.random()))
    println(chars.randomOrNull(Random(5)))
    println(chars.randomOrNull() != null)

    val booleans = booleanArrayOf(true, false)
    println(booleans.random(Random(42)))
    println(booleans.randomOrNull(Random(6)))
    println(booleans.randomOrNull() != null)

    val floats = floatArrayOf(1.5f, 2.5f)
    println(floats.random(Random(42)))
    println(floats.toList().contains(floats.random()))
    println(floats.randomOrNull(Random(7)))
    println(floats.randomOrNull() != null)

    val doubles = doubleArrayOf(1.5, 2.5)
    println(doubles.random(Random(42)))
    println(doubles.toList().contains(doubles.random()))
    println(doubles.randomOrNull(Random(8)))
    println(doubles.randomOrNull() != null)

    val strings = arrayOf("x", "y", "z")
    println(strings.random(Random(42)))
    println(strings.toList().contains(strings.random()))
    println(strings.randomOrNull(Random(9)))
    println(strings.randomOrNull() != null)
    println(emptyArray<Int>().randomOrNull())
    try {
        emptyArray<Int>().random()
        println(false)
    } catch (e: NoSuchElementException) {
        println(e.message)
    }
    try {
        intArrayOf().random(Random(11))
        println(false)
    } catch (e: NoSuchElementException) {
        println(e.message)
    }

    // Map receivers still resolve through entries (Collection overload).
    println(mapOf(1 to 2).entries.random())
    println(mapOf(1 to 2).entries.randomOrNull())

    unsignedArrays()
}
