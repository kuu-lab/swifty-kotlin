import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

// KUU-4032: CopyOnWriteArrayList / LinkedBlockingQueue. Single-threaded,
// deterministic output only — blocking calls always use bounded timeouts.
fun main() {
    // --- CopyOnWriteArrayList ---
    val cow = CopyOnWriteArrayList<Int>()
    println(cow.isEmpty())                          // true
    println(cow.add(1))                             // true
    cow.add(2)
    cow.add(3)
    println(cow.size)                               // 3
    println(cow[1])                                 // 2
    println(cow.set(1, 9))                          // 2
    println(cow)                                    // [1, 9, 3]
    println(cow.addIfAbsent(3))                     // false
    println(cow.addIfAbsent(4))                     // true
    println(cow.addAllAbsent(listOf(4, 5, 6)))      // 2
    println(cow)                                    // [1, 9, 3, 4, 5, 6]
    println(cow.indexOf(9))                         // 1
    println(cow.indexOf(9, 2))                      // -1
    println(cow.lastIndexOf(9, 4))                  // 1
    println(cow.contains(6))                        // true
    println(cow.removeAt(0))                        // 1
    println(cow.remove(9))                          // true
    cow.add(2, 99)
    println(cow)                                    // [3, 4, 99, 5, 6]
    println(cow.subList(1, 3))                      // [4, 99]

    // Iterators are snapshots: they never see later mutation and their
    // mutators throw UnsupportedOperationException.
    val snapshot = cow.iterator()
    cow.add(777)
    val seen = ArrayList<Int>()
    while (snapshot.hasNext()) seen.add(snapshot.next())
    println(seen)                                   // [3, 4, 99, 5, 6]
    try {
        snapshot.remove()
        println("no-throw")
    } catch (e: UnsupportedOperationException) {
        println("uoe")
    }

    println(CopyOnWriteArrayList(listOf(7, 8)))     // [7, 8]
    println(CopyOnWriteArrayList(arrayOf(7, 8)))    // [7, 8]
    println(cow == listOf(3, 4, 99, 5, 6, 777))     // true
    println(cow.clone())                            // [3, 4, 99, 5, 6, 777]

    // --- LinkedBlockingQueue ---
    val q = LinkedBlockingQueue<Int>(3)
    println(q.remainingCapacity())                  // 3
    println(q.offer(1))                             // true
    q.put(2)
    println(q.add(3))                               // true
    println(q.offer(4))                             // false — full
    println(q.remainingCapacity())                  // 0
    println(q.offer(5, 30, TimeUnit.MILLISECONDS))  // false — still full
    try {
        q.add(6)
        println("no-throw")
    } catch (e: IllegalStateException) {
        println("ise: ${e.message}")                // ise: Queue full
    }
    println(q.peek())                               // 1
    println(q.take())                               // 1
    println(q.poll())                               // 2
    println(q.poll(30, TimeUnit.MILLISECONDS))      // 3

    val sq = LinkedBlockingQueue<String>()
    println(sq.remainingCapacity() > 1000000)       // true — Int.MAX_VALUE bound
    sq.put("x")
    sq.put("y")
    val drained = ArrayList<String>()
    println(sq.drainTo(drained))                    // 2
    println(drained)                                // [x, y]
    println(sq.isEmpty())                           // true
    println(sq.poll(30, TimeUnit.MILLISECONDS))     // null — timed-out poll

    val qc = LinkedBlockingQueue(listOf("m", "n"))
    println(qc.size)                                // 2
    println(qc.take())                              // m
    try {
        LinkedBlockingQueue<Int>(0)
        println("no-throw")
    } catch (e: IllegalArgumentException) {
        println("iae")
    }
    try {
        sq.element()
        println("no-throw")
    } catch (e: NoSuchElementException) {
        println("nsee")
    }
    sq.add("a")
    sq.add("b")
    println(sq)                                     // [a, b]
}
