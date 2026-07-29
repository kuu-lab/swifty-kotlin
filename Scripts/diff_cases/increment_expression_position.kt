class Entry(val first: Int, val second: Int)

class EntryIterator(private val values: MutableList<Entry>) {
    private var index = 0
    operator fun hasNext(): Boolean = index < values.size
    operator fun next(): Entry = values[index++]
}

class EntryBag(private val values: MutableList<Entry>) {
    operator fun iterator(): EntryIterator = EntryIterator(values)
}

class IntArrayIterator(private val values: IntArray) {
    private var index = 0
    operator fun hasNext(): Boolean = index < values.size
    operator fun next(): Int = values[index++]
}

class IntArrayBag(private val values: IntArray) {
    operator fun iterator(): IntArrayIterator = IntArrayIterator(values)
}

class Counter {
    var value = 0
    fun postfix(): Int = value++
    fun prefix(): Int = --value
}

fun main() {
    // BUG-142: user-defined iterator over a collection stored in an instance
    // field. `values[index++]` must advance the field, otherwise the loop never
    // terminates.
    val bag = EntryBag(mutableListOf(Entry(1, 2), Entry(3, 4), Entry(5, 6)))
    val entries = bag.iterator()
    var sum = 0
    while (entries.hasNext()) {
        val e = entries.next()
        sum += e.first + e.second
    }
    println("manual=" + sum)

    var forSum = 0
    for (e in EntryBag(mutableListOf(Entry(1, 2), Entry(3, 4)))) {
        forSum += e.first + e.second
    }
    println("forin=" + forSum)

    var arraySum = 0
    for (v in IntArrayBag(intArrayOf(1, 2, 3, 4))) {
        arraySum += v
    }
    println("intarray=" + arraySum)

    // `++` / `--` in expression position on locals.
    var i = 0
    val a = arrayOf(10, 20, 30)
    println("read=" + a[i++] + " i=" + i)
    println("post=" + i++ + " i=" + i)
    println("pre=" + ++i + " i=" + i)
    println("dec=" + i-- + " i=" + i)

    // ... and on properties accessed through a receiver.
    val counter = Counter()
    println("cpost=" + counter.postfix() + " value=" + counter.value)
    println("cpre=" + counter.prefix() + " value=" + counter.value)

    // A local initialized from another variable must snapshot its value.
    var source = 1
    val snapshot = source
    source += 41
    println("snapshot=" + snapshot + " source=" + source)
}
