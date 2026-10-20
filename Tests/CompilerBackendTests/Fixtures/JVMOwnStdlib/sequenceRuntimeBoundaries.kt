fun main() {
    var drops = 0
    val dropped = sequenceOf(1, 2, 3).onEach { drops++ }.drop(1).iterator()
    println(dropped.hasNext()); println(drops); println(dropped.next()); println(drops)
    var reads = 0
    val windows = sequenceOf(1, 2, 3, 4).onEach { reads++ }.windowed(1, 3)
    val iterator = windows.iterator()
    println(reads); println(iterator.next()); println(reads)
    println(iterator.next()); println(reads); println(iterator.hasNext())
    var transforms = 0
    val chunks = sequenceOf(1, 2, 3).chunked(2) { transforms++; it.size }
    val chunkIterator = chunks.iterator()
    println(transforms); println(chunkIterator.hasNext()); println(transforms); println(chunkIterator.next())
    println(sequenceOf(1, 2).windowed(1) { null as String? }.toList())
    println(sequenceOf(1, 2, 3).zipWithNext { a, b -> null as String? }.toList())
    val text = StringBuilder("a,b,c")
    val parts = Regex(",").splitToSequence(text).iterator()
    text[0] = 'z'
    println(parts.next()); println(parts.next()); println(parts.next()); println(parts.hasNext())
    println(Regex("").splitToSequence("ab").toList())
    println(Regex(",").splitToSequence("a,b,c", 2).toList())
}
