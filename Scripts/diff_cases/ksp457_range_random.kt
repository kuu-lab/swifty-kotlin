import kotlin.random.Random

fun main() {
    val intRange = Int.MIN_VALUE..Int.MAX_VALUE
    println(intRange.random(Random(7)) in intRange)
    println(intRange.randomOrNull(Random(7)) != null)

    val longRange = Long.MIN_VALUE..Long.MAX_VALUE
    println(longRange.random(Random(7)) in longRange)
    println(longRange.randomOrNull(Random(7)) != null)

    val charRange = 'a'..'z'
    println(charRange.random(Random(7)) in charRange)
    println(charRange.randomOrNull(Random(7)) != null)

    val uintRange = 0u..UInt.MAX_VALUE
    println(uintRange.random(Random(7)) in uintRange)
    println(uintRange.randomOrNull(Random(7)) != null)

    val ulongRange = 0uL..ULong.MAX_VALUE
    println(ulongRange.random(Random(7)) in ulongRange)
    println(ulongRange.randomOrNull(Random(7)) != null)

    println((1..0).randomOrNull() == null)
    println((1L..0L).randomOrNull() == null)
    println(('b'..'a').randomOrNull() == null)
    println((1u..0u).randomOrNull() == null)
    println((1uL..0uL).randomOrNull() == null)

    try {
        (1..0).random()
        println(false)
    } catch (e: NoSuchElementException) {
        println(true)
    }
}
