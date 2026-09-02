package golden.sema

class IntIterator : MutableIterator<Int> {
    override fun hasNext(): Boolean = false

    override fun next(): Int = 0

    override fun remove(): Unit {}
}

fun acceptsAnyIterator(iterator: MutableIterator<Any>) {}

fun checksCovariance(iterator: MutableIterator<Int>) {
    acceptsAnyIterator(iterator)
}

fun checksMutableIterable(iterable: MutableIterable<Int>) {
    val iterator: MutableIterator<Int> = iterable.iterator()
    iterator.remove()
}

fun checksConcreteIterator(iterator: IntIterator) {
    iterator.remove()
}
