import structures.*
fun main() {
    val queue = Queue<Int>()
    queue.enqueue(3)
    queue.enqueue(7)
    println(queue.peek())
    println(queue.dequeue())
    println(queue.dequeue())
    println(queue.isEmpty)
}
