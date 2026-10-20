var hashes = 0
class Key(val n: Int) {
    override fun equals(other: Any?): Boolean = other is Key && n == other.n
    override fun hashCode(): Int { hashes++; return n }
}
fun main() {
    println(sequenceOf(Key(1), Key(1), Key(2)).distinct().count()); println(hashes)
    var reads = 0
    val dropped = sequenceOf(1, 2, 3).onEach { reads++ }.dropWhile { it < 2 }.iterator()
    println(dropped.next()); println(reads)
    println(dropped.hasNext()); println(reads); println(dropped.next()); println(reads)
}
