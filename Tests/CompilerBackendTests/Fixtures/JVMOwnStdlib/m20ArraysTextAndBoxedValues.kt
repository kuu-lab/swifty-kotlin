fun main() {
    println(arrayOf("a", "bb", "c").groupBy { it.length })
    println(intArrayOf(1, 2, 3).associate { it to it * 2 })
    println(charArrayOf('a', 'b').zip(listOf(1, 2)))
    println(uintArrayOf(0u, UInt.MAX_VALUE, 1u).groupBy { it > 0u })
    println(ubyteArrayOf(0u, 255u).associateWith { it.toInt() })
    println(ushortArrayOf(0u, 65535u).partition { it > 0u })
    val chars: CharSequence = StringBuilder("abcd")
    val parts = chars.partition { it < 'c' }; println(parts); println(parts.first.javaClass.name)
    val strings = "abcd".partition { it < 'c' }; println(strings); println(strings.first.javaClass.name)
    println("abca".groupBy { it }); println("abc".associate { it to it.code })
    println("abc".zip("XY")); println("abc".zip("XY") { a, b -> "$a$b" })
    println(intArrayOf(1, 2, 3).joinToString()); println(arrayOf("a", "b").joinToString { it.uppercase() })
    val array = uintArrayOf(1u, UInt.MAX_VALUE); val sequence = array.asSequence(); array[0] = 2u
    println(sequence.toList()); println(array.joinToString())
    println("a界".asSequence().map { it.code }.joinToString())
    println(arrayOf(1, 2).asSequence().toList()); println(charArrayOf('a', 'b').asSequence().toList())
    val elements = arrayOf(1, 2); val seq = sequenceOf(*elements, 3); elements[0] = 9; println(seq.toList())
}
