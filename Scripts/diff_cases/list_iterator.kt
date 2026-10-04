fun main() {
    val list = listOf(10, 20, 30)
    val iter = list.listIterator()

    // Forward traversal
    while (iter.hasNext()) {
        print("${iter.next()} ")
    }
    println()

    // Backward traversal
    while (iter.hasPrevious()) {
        print("${iter.previous()} ")
    }
    println()

    // listIterator(index) starts the cursor at the given position.
    val fromMiddle: ListIterator<Int> = list.listIterator(1)
    print("${fromMiddle.next()} ")
    print("${fromMiddle.next()} ")
    println()

    // MutableList.iterator() must be assignable to MutableIterator (covariant
    // override), and remove() through it must mutate the backing list.
    val mutable = mutableListOf(1, 2, 3, 4)
    val mutIter: MutableIterator<Int> = mutable.iterator()
    while (mutIter.hasNext()) {
        if (mutIter.next() % 2 == 0) {
            mutIter.remove()
        }
    }
    println(mutable)

    // MutableList.listIterator(index) must be assignable to MutableListIterator.
    val mutableFromMiddle: MutableListIterator<Int> = mutable.listIterator(1)
    print("${mutableFromMiddle.next()} ")
    println()
}
