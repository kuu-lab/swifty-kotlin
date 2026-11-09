// DIFF_JVM
// isEmpty/isNotEmpty/toList must cover every primitive array type, matching
// kotlin.collections' per-array declarations.
fun main() {
    println(intArrayOf(1).isEmpty())
    println(intArrayOf().isNotEmpty())
    println(longArrayOf(1L).toList())
    println(doubleArrayOf(1.5).toList())
    println(floatArrayOf(0.5f).isNotEmpty())
    println(booleanArrayOf(true).toList())
    println(charArrayOf('a').toList())
    println(byteArrayOf(1).toList())
    println(shortArrayOf(1).toList())
    println(byteArrayOf().isEmpty())
}
