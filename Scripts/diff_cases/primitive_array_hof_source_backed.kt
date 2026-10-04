// KSP-687: every primitive array family must resolve its higher-order
// operations through bundled Kotlin source. The case exercises the complete
// operation family on IntArray and representative operations on every other
// primitive array, including the ByteArray and ShortArray types introduced by
// BUG-187.
fun main() {
    val ints = intArrayOf(1, 2, 3, 4)
    println(ints.map { it * 2 })
    println(ints.mapIndexed { index, value -> index + value })
    println(ints.flatMap { listOf(it, it * 10) })
    ints.forEach { print(it) }
    println()
    println(ints.filter { it % 2 == 0 })
    println(ints.filterIndexed { index, _ -> index % 2 == 0 })
    println(ints.filterNot { it < 3 })
    println(ints.fold(0) { accumulator, value -> accumulator + value })
    println(ints.foldIndexed(0) { index, accumulator, value -> accumulator + index * value })
    println(ints.reduce { accumulator, value -> accumulator + value })
    println(ints.reduceIndexed { index, accumulator, value -> accumulator + index + value })
    println(ints.reduceOrNull { accumulator, value -> accumulator * value })
    println(ints.find { it > 2 })
    println(ints.findLast { it < 3 })
    println(ints.first())
    println(ints.first { it > 2 })
    println(ints.firstOrNull { it > 20 })
    println(ints.last())
    println(ints.last { it < 4 })
    println(ints.lastOrNull { it > 20 })
    println(ints.any())
    println(ints.any { it == 3 })
    println(ints.all { it > 0 })
    println(ints.none { it < 0 })
    println(ints.count())
    println(ints.count { it % 2 == 0 })
    println(ints.joinToString("-"))
    println(ints.joinToString("-", "[", "]") { "x$it" })

    val longs = longArrayOf(1L, 2L, 3L)
    println(longs.map { (it * 2L).toString() })
    println(longs.filter { it > 1L })
    println(longs.fold(0L) { accumulator, value -> accumulator + value })
    println(longs.joinToString(transform = { it.toString() }))

    val doubles = doubleArrayOf(1.0, 2.5, 3.5)
    println(doubles.map { (it * 2.0).toString() })
    println(doubles.filter { it > 1.0 })
    println(doubles.fold(0.0) { accumulator, value -> accumulator + value })
    println(doubles.joinToString(transform = { it.toString() }))

    val floats = floatArrayOf(1.0f, 2.5f, 3.5f)
    println(floats.map { (it * 2.0f).toString() })
    println(floats.filter { it > 1.0f })
    println(floats.fold(0.0f) { accumulator, value -> accumulator + value })
    println(floats.joinToString(transform = { it.toString() }))

    val chars = charArrayOf('a', 'b', 'c')
    println(chars.map { it.toString() })
    println(chars.filter { it > 'a' })
    println(chars.fold("") { accumulator, value -> accumulator + value })
    println(chars.joinToString(transform = { it.toString() }))

    val booleans = booleanArrayOf(true, false, true)
    println(booleans.map { it.toString() })
    println(booleans.filter { it })
    println(booleans.fold(false) { accumulator, value -> accumulator || value })
    println(booleans.joinToString(transform = { it.toString() }))

    val bytes = byteArrayOf(1, 2, 3)
    println(bytes.map { it.toInt().toString() })
    println(bytes.filter { it > 1 })
    println(bytes.fold(0) { accumulator, value -> accumulator + value })
    println(bytes.joinToString(transform = { it.toString() }))

    val shorts = shortArrayOf(1, 2, 3)
    println(shorts.map { it.toInt().toString() })
    println(shorts.filter { it > 1 })
    println(shorts.fold(0) { accumulator, value -> accumulator + value })
    println(shorts.joinToString(transform = { it.toString() }))

    val uints = uintArrayOf(1u, 2u, 3u)
    println(uints.map { (it * 2u).toString() })
    println(uints.filter { it > 1u })
    println(uints.fold(0u) { accumulator, value -> accumulator + value })
    println(uints.joinToString(transform = { it.toString() }))

    val ulongs = ulongArrayOf(1uL, 2uL, 3uL)
    println(ulongs.map { (it * 2uL).toString() })
    println(ulongs.filter { it > 1uL })
    println(ulongs.fold(0uL) { accumulator, value -> accumulator + value })
    println(ulongs.joinToString(transform = { it.toString() }))

    val ubytes = UByteArray(3) { (it + 1).toUByte() }
    println(ubytes.map { (it * 2u).toString() })
    println(ubytes.filter { it > 1u })
    println(ubytes.fold(0u) { accumulator, value -> accumulator + value })
    println(ubytes.joinToString(transform = { it.toString() }))

    val ushorts = UShortArray(3) { (it + 1).toUShort() }
    println(ushorts.map { (it * 2u).toString() })
    println(ushorts.filter { it > 1u })
    println(ushorts.fold(0u) { accumulator, value -> accumulator + value })
    println(ushorts.joinToString(transform = { it.toString() }))
}
