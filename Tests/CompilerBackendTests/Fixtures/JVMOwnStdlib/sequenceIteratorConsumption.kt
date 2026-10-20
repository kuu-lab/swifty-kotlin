var checks = 0
var reads = 0
fun source(): Sequence<Int> = object: Sequence<Int> {
    override fun iterator(): Iterator<Int> = object: Iterator<Int> {
        var index = 0
        override fun hasNext(): Boolean { checks++; return index < 3 }
        override fun next(): Int { reads++; return ++index }
    }
}
class Key(val n: Int) {
    override fun equals(other: Any?): Boolean = other is Key && n == other.n
    override fun hashCode(): Int { hashes++; return n }
}
var hashes = 0
fun main() {
    println(sequenceOf(Key(1), Key(1), Key(2)).distinct().count()); println(hashes)
    val dropped = source().dropWhile { it < 2 }.iterator()
    println(dropped.next()); println(reads)
    println(dropped.hasNext()); println(reads); println(dropped.next()); println(reads)
    checks = 0; reads = 0
    val mapped = source().mapIndexed { i, n -> i + n }.iterator()
    println(mapped.next()); println(checks); println(reads)
    checks = 0; reads = 0
    val zipped = source().zip(sequenceOf(10, 20)).iterator()
    println(zipped.next()); println(checks); println(reads)
    checks = 0; reads = 0
    val taken = source().take(2).iterator()
    println(taken.next()); println(checks); println(reads)
}
