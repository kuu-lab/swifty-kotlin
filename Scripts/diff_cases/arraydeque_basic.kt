fun main() {
    val deque = ArrayDeque<Int>()
    deque.addFirst(1)
    deque.addLast(2)
    deque.addFirst(0)
    println(deque.first())
    println(deque.last())
    println(deque.size)
    println(deque.isEmpty())
    println(deque[0])
    println(deque[2])
    println(deque.toString())
    deque.removeFirst()
    println(deque.first())
    deque.removeLast()
    println(deque.last())
    println(deque.toString())

    // Ring-buffer wraparound: repeated pushes/pops at both ends must keep the
    // logical order intact even after the head wraps past the buffer end.
    val ring = ArrayDeque<Int>()
    var i = 0
    while (i < 12) {
        ring.addLast(i)
        i += 1
    }
    var popped = 0
    while (popped < 9) {
        ring.removeFirst()
        popped += 1
    }
    var j = 100
    while (j < 108) {
        ring.addLast(j)
        ring.addFirst(j)
        j += 1
    }
    println(ring.size)
    println(ring.first())
    println(ring.last())
    println(ring[0])
    println(ring[ring.size - 1])
    println(ring.toString())
    while (!ring.isEmpty()) {
        ring.removeLast()
    }
    println(ring.size)
    println(ring.isEmpty())
    println(ring.toString())

    val strings = ArrayDeque<String>()
    println(strings.isEmpty())
    println(strings.isNotEmpty())
    println(strings.firstOrNull())
    println(strings.lastOrNull())
    println(strings.removeFirstOrNull())
    println(strings.removeLastOrNull())
    strings.addLast("b")
    strings.addFirst("a")
    strings.addLast("c")
    println(strings.toString())
    println(strings[1])
    println(strings.removeFirst())
    println(strings.removeLast())
    println(strings.toString())

    try {
        ArrayDeque<Int>().first()
    } catch (e: NoSuchElementException) {
        println("first: " + e.message)
    }
    try {
        ArrayDeque<Int>().removeLast()
    } catch (e: NoSuchElementException) {
        println("removeLast: " + e.message)
    }
    try {
        val single = ArrayDeque<Int>()
        single.addLast(7)
        println(single[3])
    } catch (e: IndexOutOfBoundsException) {
        println("get: " + e.message)
    }
}
