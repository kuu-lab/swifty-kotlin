fun main() {
    val ints = IntProgression.fromClosedRange(2, 11, 3)
    println("${ints.first}:${ints.last}:${ints.step}:$ints")
    println(ints == IntProgression.fromClosedRange(2, 8, 3))

    val longs = LongProgression.fromClosedRange(10L, 1L, -3)
    println("${longs.first}:${longs.last}:${longs.step}:$longs")

    val chars = CharProgression.fromClosedRange('a', 'g', 2)
    println("${chars.first}:${chars.last}:${chars.step}:$chars")

    val uints = UIntProgression.fromClosedRange(2u, 11u, 3)
    println("${uints.first}:${uints.last}:${uints.step}:$uints")

    val ulongs = ULongProgression.fromClosedRange(10uL, 1uL, -3L)
    println("${ulongs.first}:${ulongs.last}:${ulongs.step}:$ulongs")
}
