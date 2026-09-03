private class ProbeListIterator : ListIterator<Int> {
    private var cursor = 0

    override fun hasNext(): Boolean = cursor < 2

    override fun next(): Int {
        if (!hasNext()) throw NoSuchElementException()
        val value = cursor + 10
        cursor += 1
        return value
    }

    override fun hasPrevious(): Boolean = cursor > 0

    override fun previous(): Int {
        if (!hasPrevious()) throw NoSuchElementException()
        cursor -= 1
        return cursor + 10
    }

    override fun nextIndex(): Int = cursor

    override fun previousIndex(): Int = cursor - 1
}

fun main() {
    val builtIn: ListIterator<Int> = listOf(10, 20, 30).listIterator()
    print("${builtIn.nextIndex()}/${builtIn.previousIndex()} ")
    print("${builtIn.next()} ")
    print("${builtIn.nextIndex()}/${builtIn.previousIndex()} ")
    print("${builtIn.previous()} ")

    val builtInBoundary: ListIterator<Int> = listOf(40).listIterator()
    try {
        builtInBoundary.previous()
    } catch (_: NoSuchElementException) {
        print("built-in-boundary ")
    }

    val builtInNextBoundary: ListIterator<Int> = listOf(50).listIterator()
    try {
        builtInNextBoundary.next()
        builtInNextBoundary.next()
    } catch (_: NoSuchElementException) {
        print("built-in-next-boundary ")
    }

    val custom: ListIterator<Int> = ProbeListIterator()
    print("${custom.hasNext()} ${custom.next()} ${custom.next()} ")
    print("${custom.hasPrevious()} ${custom.previous()} ")
    try {
        custom.previous()
        custom.previous()
    } catch (_: NoSuchElementException) {
        print("boundary ")
    }
    print("${custom.nextIndex()}/${custom.previousIndex()}")
}
