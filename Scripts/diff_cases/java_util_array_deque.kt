import java.util.ArrayDeque

fun hailstone(n: Int): ArrayDeque<Int> {
    val hails = ArrayDeque<Int>()
    hails.addFirst(n)
    return hails
}

fun main() {
    val deque = ArrayDeque<Int>()
    deque.addFirst(2)
    deque.addLast(3)
    println(deque.first)
    println(deque.last)
    println(deque.peekFirst())
    println(deque.peekLast())
    println(deque.offerFirst(1))
    println(deque.offerLast(4))
    println(deque)
    println(deque.pollFirst())
    println(deque.pollLast())
    println(deque)
    println(deque.removeFirstOccurrence(3))
    println(deque.first)
    println(deque.removeLastOccurrence(2))
    println(deque.isEmpty())

    val copied = ArrayDeque<Int>(listOf(5, 6))
    println("${copied.remove()} ${copied.element()} ${copied.peek()}")
    copied.push(4)
    println("${copied.pop()} ${copied.poll()}")
    println(hailstone(7).first)
}
