fun main() {
    val absent: Int? = null
    val inside: Int? = 3
    val outside: Int? = 7
    val range = 1..5
    println(range.contains(null))
    println(range.contains(absent))
    println(range.contains(inside))
    println(range.contains(outside))
    println(absent in range)
    println(inside in range)
    println(outside !in range)
    println(absent !in range)
    println(inside in 5..1)
    val longValue: Long? = 3L
    val noLong: Long? = null
    println((1L..5L).contains(longValue))
    println(noLong in 1L..5L)
    val charValue: Char? = 'c'
    val noChar: Char? = null
    println(('a'..'e').contains(charValue))
    println(noChar in 'a'..'e')
    val unsignedValue: UInt? = 3u
    val noUInt: UInt? = null
    println((1u..5u).contains(unsignedValue))
    println(noUInt in 1u..5u)
    val ulongValue: ULong? = 3uL
    val noULong: ULong? = null
    println((1uL..5uL).contains(ulongValue))
    println(noULong in 1uL..5uL)
    println(3 in range)
    println(range.contains(7))
}
