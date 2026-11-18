// DIFF_JVM
// KUU-4612: java.util.Queue.size is a Kotlin property on the JVM backend,
// matching kotlinc's mapped-type behavior — Queue-typed receivers and Queue
// subtypes (ArrayDeque, LinkedList, PriorityQueue, LinkedBlockingQueue) read
// .size without call parentheses.
import java.util.Queue
import java.util.ArrayDeque
import java.util.LinkedList
import java.util.PriorityQueue
import java.util.concurrent.LinkedBlockingQueue

fun main() {
    val q: Queue<Int> = ArrayDeque<Int>()
    q.offer(10)
    q.offer(20)
    println(q.size)
    println(q.element())
    println(q.poll())
    println(q.size)

    val lq: Queue<String> = LinkedList<String>()
    lq.add("a")
    lq.add("b")
    lq.add("c")
    println(lq.size)
    println(lq.peek())

    val pq: Queue<Int> = PriorityQueue<Int>()
    pq.offer(5)
    pq.offer(1)
    println(pq.size)
    println(pq.poll())
    println(pq.size)

    // Concrete Queue implementations expose the same property.
    val ad = ArrayDeque<String>()
    ad.add("x")
    ad.add("y")
    println(ad.size)

    val lbq = LinkedBlockingQueue<String>(4)
    lbq.add("p")
    lbq.add("q")
    println(lbq.size)
    println(lbq.poll())
    println(lbq.size)
}
