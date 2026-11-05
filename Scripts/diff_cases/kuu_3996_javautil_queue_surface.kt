// KUU-3996: bundled java.util.Queue/ArrayDeque/PriorityQueue API surface —
// Queue-typed receivers over the FIFO shims, the Queue.remove() head
// operation, and the PriorityQueue Collection/PriorityQueue/SortedSet
// constructors with JDK ordering preservation (a SortedSet or PriorityQueue
// argument keeps its comparator even through a Collection-typed reference).
import java.util.Queue
import java.util.ArrayDeque
import java.util.LinkedList
import java.util.PriorityQueue
import java.util.TreeSet

fun drainQueue(q: Queue<Int>): List<Int> {
    val out = mutableListOf<Int>()
    while (!q.isEmpty()) out.add(q.remove())
    return out
}

fun main() {
    // ArrayDeque -> Queue assignment and head operations.
    val q: Queue<Int> = ArrayDeque<Int>()
    q.offer(10)
    q.offer(20)
    q.offer(30)
    println(q.element())
    println(q.peek())
    println(q.poll())
    println(q.remove())
    println(q.size)
    println(drainQueue(q))
    println(q.isEmpty())
    try { q.element() } catch (e: NoSuchElementException) { println("element-empty") }
    try { q.remove() } catch (e: NoSuchElementException) { println("remove-empty") }
    val emptyPeek: Int? = q.peek()
    val emptyPoll: Int? = q.poll()
    println("$emptyPeek,$emptyPoll")

    // LinkedList satisfies Queue too (on the JVM via Deque).
    val lq: Queue<String> = LinkedList<String>()
    lq.offer("a")
    lq.offer("b")
    println(lq.element())
    println(lq.poll())
    println(lq.remove())
    println(lq.isEmpty())

    // PriorityQueue -> Queue receiver.
    val pqIf: Queue<Int> = PriorityQueue<Int>()
    pqIf.offer(42)
    println(pqIf.element())
    println(pqIf.poll())

    // PriorityQueue(Collection) drains in heap order.
    val p = PriorityQueue(listOf(5, 1, 4, 2, 3))
    println(drainQueue(p))

    // PriorityQueue(PriorityQueue) keeps the source comparator.
    val descending = PriorityQueue<Int>(Comparator { a, b -> b.compareTo(a) })
    descending.offer(1)
    descending.offer(9)
    descending.offer(5)
    val copied = PriorityQueue(descending)
    println(drainQueue(copied))
    println(copied.comparator() != null)

    // PriorityQueue(SortedSet) keeps the sorted set ordering.
    val ts = TreeSet<Int>(Comparator { a, b -> b.compareTo(a) })
    ts.add(7); ts.add(3); ts.add(9)
    val fromSet = PriorityQueue(ts)
    println(drainQueue(fromSet))

    // A SortedSet or PriorityQueue passed through a Collection-typed
    // reference still keeps its ordering (JDK instanceof dispatch inside
    // the Collection constructor).
    val erasedSet: Collection<Int> = ts
    println(drainQueue(PriorityQueue(erasedSet)))
    val erasedQueue: Collection<Int> = descending
    println(drainQueue(PriorityQueue(erasedQueue)))
}
