// KSP-633: `MutableIterable` / `AbstractCollection` / `AbstractMutableCollection` are
// source-backed by `Sources/CompilerCore/Stdlib/kotlin/collections/`. This case locks
// the observable behavior of a user implementation of `MutableIterable` /
// `MutableIterator` against kotlinc.
//
// Subclasses of the skeletal `AbstractCollection` / `AbstractMutableCollection`
// classes are not exercised here: through a precompiled stdlib artifact
// (`--stdlib-library`, which is how this harness compiles cases) imported classes
// lose their declared modality, so inheriting from them is rejected. That gap is
// pre-existing (it reproduces on the pre-KSP-633 synthetic declarations too) and is
// tracked as BUG-183.

class BagIterator(private val items: ArrayList<Int>) : MutableIterator<Int> {
    private var index = 0

    override fun hasNext(): Boolean = index < items.size

    override fun next(): Int {
        val value = items[index]
        index += 1
        return value
    }

    override fun remove() {
        index -= 1
        items.removeAt(index)
    }
}

class Countdown(private val from: Int) : MutableIterable<Int> {
    val items = ArrayList<Int>()

    private fun fill() {
        if (items.size > 0) return
        var value = from
        while (value > 0) {
            items.add(value)
            value -= 1
        }
    }

    override fun iterator(): MutableIterator<Int> {
        fill()
        return BagIterator(items)
    }
}

fun main() {
    val countdown = Countdown(4)

    val summing = countdown.iterator()
    var total = 0
    while (summing.hasNext()) {
        total += summing.next()
    }
    println(total)
    println(countdown.items.size)

    val dropping = countdown.iterator()
    dropping.next()
    dropping.remove()
    println(countdown.items.size)
    println(countdown.items)
}
