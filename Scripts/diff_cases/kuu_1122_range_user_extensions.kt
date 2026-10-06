// KUU-1122: inferred range receivers must resolve user extensions.
fun IntRange.onRange() = "int"
fun LongRange.onRange() = "long"
fun CharRange.onRange() = "char"
fun <T> Iterable<T>.genExt() = "gen"
fun Int.scalarOrRange() = "scalar"
fun IntRange.scalarOrRange() = "range"
fun <T> Iterable<T>.firstViaExtension(): T = first()

fun main() {
    val r1 = 1..3
    println(r1.onRange())
    println(r1.genExt())
    println((1..3).genExt())
    val r2: IntRange = 1..3
    println(r2.genExt())
    val longs = 1L..3L
    val chars = 'a'..'c'
    println(longs.onRange())
    println(longs.genExt())
    println((1L..3L).genExt())
    println(chars.onRange())
    println(chars.genExt())
    println(('a'..'c').genExt())
    println(r1.scalarOrRange())
    println(1.scalarOrRange())
    println(r1.firstViaExtension())
    println(longs.firstViaExtension())
    println(chars.firstViaExtension())
}
