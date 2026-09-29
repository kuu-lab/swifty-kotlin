package golden.sema

// KSP-1063: List interface member declarations — size/get/isEmpty/iterator/
// listIterator()/listIterator(index) on a statically List-typed receiver.

fun listSize(values: List<Int>): Int = values.size

fun listIsEmpty(values: List<Int>): Boolean = values.isEmpty()

fun listGet(values: List<Int>): Int = values[1]

fun listIteratorProbe(values: List<Int>): Int {
    val iterator = values.iterator()
    var sum = 0
    while (iterator.hasNext()) {
        sum += iterator.next()
    }
    return sum
}

fun listIndexedIteratorProbe(values: List<Int>): Int {
    val iterator = values.listIterator(1)
    var sum = 0
    while (iterator.hasNext()) {
        sum += iterator.next()
    }
    while (iterator.hasPrevious()) {
        sum += iterator.previous()
    }
    return sum
}

fun listForProbe(values: List<Int>): Int {
    var sum = 0
    for (value in values) {
        sum += value
    }
    return sum
}
