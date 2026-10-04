// KUU-589: Kotlin strings compare and index UTF-16 code units without
// applying Unicode canonical-equivalence normalization.
fun main() {
    val composed = 0x00E9.toChar().toString()
    val decomposed = "e" + 0x0301.toChar()

    println("equal=${composed == decomposed}")
    println("length=${decomposed.length}")
    println("first=${decomposed.first().code}")
    println("units=${decomposed.toList().map { it.code }}")
    println("hash=${composed.hashCode()}/${decomposed.hashCode()}")
    println("map=${mapOf(composed to 1)[decomposed]}")
    println("index=${decomposed.indexOf(0x0301.toChar())}")
    println("replace=${decomposed.replace("e", "a")}")
    println("angstrom=${0x00C5.toChar().toString() == 0x212B.toChar().toString()}")
    println("distinct=${listOf(composed, decomposed).distinct().size}")

    val emoji = "😀"
    val reversedEmoji: String = emoji.reversed()
    println("emojiHash=${emoji.hashCode()}")
    println("compare=${emoji.compareTo(0xE000.toChar().toString())}")
    println("reversedUnits=${reversedEmoji.toList().map { it.code }}")
}
