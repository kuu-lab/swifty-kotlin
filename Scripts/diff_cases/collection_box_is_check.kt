fun checkIterator(value: Any) {
    println(value is Iterator<*>)
    println(value is Iterable<*>)
    println(value is List<*>)
    println(value is Sequence<*>)
    if (value is Iterator<*>) {
        println(value.hasNext())
        println(value.next())
    }
    println(value as? List<*>)
}

fun exhaustIterator(value: Any) {
    val iterator = value as Iterator<*>
    println(iterator.next())
    println(iterator.hasNext())
    try {
        iterator.next()
        println("unexpected")
    } catch (e: NoSuchElementException) {
        println("iterator exhausted")
    }
}

fun main() {
    val it = listOf(1, 2, 3).iterator()
    println(it is Iterator<*>)
    checkIterator(listOf(10, 20).iterator())
    checkIterator(setOf(30, 40).iterator())
    checkIterator(mapOf(1 to "a").entries.iterator())
    checkIterator(sequenceOf(50, 60).iterator())
    checkIterator(generateSequence(70) { it + 1 }.iterator())
    checkIterator(iterator { yield(80) })
    checkIterator(listOf(90).withIndex().iterator())

    val erased: Any = listOf(100).iterator()
    val cast = erased as Iterator<*>
    println(cast.hasNext())
    println(cast.next())
    println(cast.hasNext())
    println((erased as? Iterator<*>) != null)
    try {
        erased as List<*>
        println("unexpected")
    } catch (e: ClassCastException) {
        println("wrong cast rejected")
    }

    val mutable = mutableListOf(1, 2)
    val mutableIterator: Any = mutable.iterator()
    println(mutableIterator is MutableIterator<*>)
    if (mutableIterator is MutableIterator<*>) {
        println(mutableIterator.next())
        mutableIterator.remove()
    }
    println(mutable)

    val sequence: Any = sequenceOf(3)
    println(sequence is Sequence<*>)
    println(sequence is Iterable<*>)
    println((sequence as Sequence<*>).iterator().next())
    val indexed: Any = listOf(4).withIndex()
    println(indexed is Iterable<*>)
    println(indexed is Collection<*>)
    println((indexed as Iterable<*>).iterator().next())
    val list: Any = listOf(5)
    println(list is List<*>)
    println(list is Sequence<*>)
    exhaustIterator(sequenceOf(6).iterator())
    exhaustIterator(generateSequence(7) { null }.iterator())
}
