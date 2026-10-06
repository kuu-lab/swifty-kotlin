fun main() {
    // remove() right after add(): add() invalidates the cursor position,
    // so a following remove() (with no intervening next()) must throw.
    val afterAdd = mutableListOf(1, 2, 3).listIterator()
    afterAdd.next()
    afterAdd.add(25)
    try {
        afterAdd.remove()
        println("remove-after-add: not-thrown")
    } catch (e: IllegalStateException) {
        println("remove-after-add: caught")
    }

    // remove() before any next()/previous() call.
    val beforeNext = mutableListOf(1, 2, 3).listIterator()
    try {
        beforeNext.remove()
        println("remove-before-next: not-thrown")
    } catch (e: IllegalStateException) {
        println("remove-before-next: caught")
    }

    // set() before any next()/previous() call.
    val setBeforeNext = mutableListOf(1, 2, 3).listIterator()
    try {
        setBeforeNext.set(9)
        println("set-before-next: not-thrown")
    } catch (e: IllegalStateException) {
        println("set-before-next: caught")
    }

    // A second remove() right after the first, with no intervening next().
    val doubleRemove = mutableListOf(1).iterator()
    doubleRemove.next()
    doubleRemove.remove()
    try {
        doubleRemove.remove()
        println("double-remove: not-thrown")
    } catch (e: IllegalStateException) {
        println("double-remove: caught")
    }
}
