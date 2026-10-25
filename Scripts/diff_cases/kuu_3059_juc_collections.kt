import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue

// KUU-3059: ConcurrentHashMap / ConcurrentLinkedQueue. Single-threaded,
// deterministic output only — view snapshots never reach stdout.
fun main() {
    val map = ConcurrentHashMap<String, Int>()
    println(map.size)                       // 0
    println(map.isEmpty())                  // true
    println(map.putIfAbsent("k", 1))        // null
    println(map.putIfAbsent("k", 9))        // 1
    println(map["k"])                       // 1
    println(map.replace("k", 1, 2))         // true
    println(map.replace("k", 99))           // 2
    println(map.getOrDefault("k", -1))      // 99
    println(map.getOrDefault("missing", -1))// -1
    println(map.remove("k", 0))             // false
    println(map.remove("k"))                // 99
    println(map.containsKey("k"))           // false
    map["a"] = 1
    map["b"] = 2
    println(map.size)                       // 2
    println(map.computeIfAbsent("c") { it.length }) // 1
    println(map.computeIfAbsent("a") { it.length }) // 1

    val queue = ConcurrentLinkedQueue<Int>()
    println(queue.isEmpty())                // true
    println(queue.offer(1))                 // true
    queue.add(2)
    queue.add(3)
    println(queue.size)                     // 3
    println(queue.peek())                   // 1
    println(queue.poll())                   // 1
    println(queue.element())                // 2
    println(queue.contains(3))              // true
    println(queue.remove(3))                // true
    println(queue.poll())                   // 2
    println(queue.isEmpty())                // true
    println(queue.toString())               // []
}
