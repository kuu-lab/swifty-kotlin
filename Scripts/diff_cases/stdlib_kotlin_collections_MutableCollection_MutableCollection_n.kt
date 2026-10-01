// KUU-677: mutable member calls through the MutableCollection interface.
fun exercise(collection: MutableCollection<Int>) {
    println(collection.add(4))
    println(collection.addAll(listOf(2, 3)))
    println(collection.remove(2))
    println(collection.removeAll(listOf(3)))
    println(collection.retainAll(listOf(4)))
    val iterator: MutableIterator<Int> = collection.iterator()
    while (iterator.hasNext()) println(iterator.next())
    collection.clear()
    println(collection.size)
}

fun main() {
    exercise(mutableListOf(1))
    exercise(mutableSetOf(1))
}
