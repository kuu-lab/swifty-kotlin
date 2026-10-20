fun mapIndexedSourceFailure() {
    var first = true
    val source = sequenceOf(10, 20).map { if (first) { first = false; throw IllegalArgumentException("source") }; it }
    val iterator = source.mapIndexed { index, value -> "$index:$value" }.iterator()
    try { iterator.next() } catch (failure: IllegalArgumentException) { println("caught") }
    println(iterator.next()); println(iterator.hasNext())
}

fun onEachIndexedSourceFailure() {
    var first = true
    val source = sequenceOf(10, 20).map { if (first) { first = false; throw IllegalArgumentException("source") }; it }
    val iterator = source.onEachIndexed { index, value -> println("$index:$value") }.iterator()
    try { iterator.next() } catch (failure: IllegalArgumentException) { println("caught") }
    println(iterator.next()); println(iterator.hasNext())
}

fun mapIndexedNotNullSourceFailure() {
    var first = true
    val source = sequenceOf(10, 20).map { if (first) { first = false; throw IllegalArgumentException("source") }; it }
    val iterator = source.mapIndexedNotNull { index, value -> "$index:$value" }.iterator()
    try { iterator.next() } catch (failure: IllegalArgumentException) { println("caught") }
    println(iterator.next()); println(iterator.hasNext())
}

fun filterIndexedSourceFailure() {
    var first = true
    val source = sequenceOf(10, 20).map { if (first) { first = false; throw IllegalArgumentException("source") }; it }
    val iterator = source.filterIndexed { index, value -> println("$index:$value"); true }.iterator()
    try { iterator.next() } catch (failure: IllegalArgumentException) { println("caught") }
    println(iterator.next()); println(iterator.hasNext())
}

fun main() { mapIndexedSourceFailure(); onEachIndexedSourceFailure(); mapIndexedNotNullSourceFailure(); filterIndexedSourceFailure() }
