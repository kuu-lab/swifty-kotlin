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
    println(deque[deque.size - 1])
    deque.removeFirst()
    println(deque.first())
    deque.removeLast()
    println(deque.last())
    println(deque.toString())

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
    println(strings)
    println(strings.removeFirst())
    println(strings.removeLast())
    println(strings)

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
