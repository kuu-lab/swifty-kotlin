// BUG-200: imported generic skeletal collections must preserve modality and
// substitute the owner's type argument into inherited member signatures.

import kotlin.collections.AbstractCollection
import kotlin.collections.Iterator

class EmptyIntIterator : Iterator<Int> {
    override fun hasNext(): Boolean = false

    override fun next(): Int = 0
}

class EvenNumbers : AbstractCollection<Int>() {
    override val size: Int
        get() = 0

    override fun iterator(): Iterator<Int> = EmptyIntIterator()
}

fun main() {
    println(EvenNumbers().size)
}
