// KUU-3869: bundled java.util Queue/Deque-family shims declare `E?` where the
// JVM signature is an unannotated `E`. Kotlin/JVM resolves the result as the
// flexible platform type `E!`, so bare member calls and non-null targets are
// legal while empty results still surface a real null (and a runtime NPE on
// unchecked non-null use). The same `T?` -> `T!` contract covers the sorted
// navigable views, the concurrent-map conditional updates, and Properties.
import java.util.LinkedList
import java.util.ArrayDeque
import java.util.PriorityQueue
import java.util.Queue
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentMap
import java.util.TreeMap
import java.util.TreeSet
import java.util.Properties

fun takeInt(value: Int) { println("take:$value") }

fun main() {
    // KUU-3869 minimal reproducer (Graph.kt pattern)
    val queue = LinkedList<Int>()
    queue.add(3)
    queue.add(7)
    val head = queue.pollFirst()
    println(head + 1)
    println(queue.isEmpty())

    // LinkedList poll/peek family — bare member ops on platform returns
    val list = LinkedList<String>()
    list.add("a")
    list.add("b")
    println(list.peek() + "x")
    println(list.peekFirst() + "y")
    println(list.peekLast() + "z")
    println(list.poll() + "p")
    println(list.pollFirst() + "q")
    println(list.pollLast() + "r")

    // Empty results are still a genuine null: `?.`, `== null`, nullable
    // bindings keep working, unchecked non-null use raises NPE.
    val emptyList = LinkedList<Int>()
    println("empty-poll:${emptyList.pollFirst() == null}:${emptyList.pollLast()}:${emptyList.peek()}")
    val nullable: Int? = emptyList.pollFirst()
    println("nullable-bind:$nullable")
    println("safe-chain:${emptyList.pollFirst()?.plus(1)}")
    try {
        val v: Int = emptyList.pollFirst()
        println("unexpected:$v")
    } catch (e: NullPointerException) {
        println("npe:pollFirst")
    }
    try {
        println(emptyList.pollFirst() + 1)
    } catch (e: NullPointerException) {
        println("npe:unbox")
    }

    // java.util.ArrayDeque
    val deque = ArrayDeque<Int>()
    deque.add(1)
    deque.add(2)
    deque.add(3)
    println("deque:${deque.peek()}:${deque.peekFirst() + 10}:${deque.peekLast() + 20}")
    println("deque-poll:${deque.poll() + 1}:${deque.pollFirst() + 1}:${deque.pollLast() + 1}:${deque.size}")
    val emptyDeque = ArrayDeque<Int>()
    println("deque-empty:${emptyDeque.pollFirst() == null}:${emptyDeque.peekLast()}")

    // PriorityQueue.peek joins poll() from KUU-3373.
    val pq = PriorityQueue<Int>()
    pq.add(9)
    println("pq:${pq.peek() + 1}:${pq.poll() + 1}")
    println("pq-empty:${pq.peek() == null}:${pq.poll() == null}")

    // Queue interface receiver
    val q2: Queue<Int> = ConcurrentLinkedQueue<Int>()
    q2.add(5)
    println("queue-iface:${q2.poll() + 1}:${q2.peek() == null}")
    val clq = ConcurrentLinkedQueue<Int>()
    clq.add(4)
    println("clq:${clq.poll() + 1}:${clq.peek() == null}")

    // NavigableSet members through the concrete TreeSet receiver
    val ts = TreeSet<Int>()
    ts.add(10)
    ts.add(20)
    ts.add(30)
    println("navset:${ts.lower(20) + 1}:${ts.floor(21)}:${ts.ceiling(19) + 1}:${ts.higher(10)}")
    println("navset-miss:${ts.lower(10) == null}:${ts.higher(30) == null}")
    println("navset-poll:${ts.pollFirst() + 1}:${ts.pollLast() + 1}")

    // NavigableMap key and entry lookups; platform `MutableEntry` exposes
    // bare `.key`/`.value` like the JVM contract.
    val tm = TreeMap<Int, String>()
    tm[1] = "one"
    tm[2] = "two"
    println("navmap:${tm.lowerKey(2) + 1}:${tm.floorKey(3)}:${tm.ceilingKey(0)}:${tm.higherKey(1) == null}")
    println("navmap-entry:${tm.firstEntry().key}:${tm.firstEntry().value}:${tm.lastEntry().value}")
    println("navmap-poll:${tm.pollFirstEntry().key}:${tm.pollLastEntry().value}:${tm.size}")
    println("navmap-empty:${tm.firstEntry() == null}:${tm.pollFirstEntry() == null}")

    // ConcurrentMap conditional-update returns through the interface and
    // the concrete ConcurrentHashMap.
    val chm = ConcurrentHashMap<Int, String>()
    chm[1] = "a"
    println("chm:${chm.putIfAbsent(1, "x")}:${chm.putIfAbsent(2, "b") == null}:${chm.replace(1, "a", "z")}")
    println("chm-replace:${chm.replace(1, "y") + "!"}:${chm.replace(9, "q") == null}")
    val cm: ConcurrentMap<Int, String> = chm
    println("cm:${cm.putIfAbsent(1, "w")}:${cm.putIfAbsent(3, "c") == null}:${cm.replace(3, "d") == null}")
    println("chm-compute:${chm.computeIfAbsent(4) { k -> "v$k" }}:${chm.computeIfAbsent(4) { "w" }}")

    // Properties.getProperty is a platform String on the JVM signature.
    val props = Properties()
    props.setProperty("k", "v")
    println("props:${props.getProperty("k") + "!"}:${props.getProperty("absent") == null}")

    takeInt(LinkedList<Int>().apply { add(1) }.pollFirst())
}
