private class ProbeListIterator : ListIterator<Int> {
    override fun hasNext(): Boolean {
        print("[hasNext]")
        return true
    }

    override fun next(): Int {
        print("[next]")
        return 111
    }

    override fun hasPrevious(): Boolean {
        print("[hasPrevious]")
        return true
    }

    override fun previous(): Int {
        print("[previous]")
        return 222
    }

    override fun nextIndex(): Int {
        print("[nextIndex]")
        return 333
    }

    override fun previousIndex(): Int {
        print("[previousIndex]")
        return 444
    }
}

fun main() {
    val viaIterator: Iterator<Int> = ProbeListIterator()
    print("hasNext=${viaIterator.hasNext()} next=${viaIterator.next()} ")

    val viaListIterator: ListIterator<Int> = ProbeListIterator()
    print("hasNext=${viaListIterator.hasNext()} next=${viaListIterator.next()} ")
    print("hasPrevious=${viaListIterator.hasPrevious()} previous=${viaListIterator.previous()} ")
    print("nextIndex=${viaListIterator.nextIndex()} previousIndex=${viaListIterator.previousIndex()}")
}
