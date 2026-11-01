import java.util.concurrent.ConcurrentNavigableMap
import java.util.concurrent.ConcurrentMap
import java.util.concurrent.ConcurrentSkipListMap
import java.util.concurrent.ConcurrentSkipListSet
import java.util.NavigableMap
import java.util.NavigableSet
import java.util.SortedSet
import java.util.TreeMap
import java.util.TreeSet

// KUU-4118: ConcurrentSkipListSet / ConcurrentSkipListMap — sorted ordering,
// null rejection, ConcurrentMap conditional updates, and Navigable views.
// Single-threaded deterministic output only.
fun main() {
    // --- ConcurrentSkipListSet ---
    val s = ConcurrentSkipListSet<Int>()
    println(s.add(3))                                   // true
    s.add(1)
    s.add(2)
    println(s.add(2))                                   // false
    println(s)                                          // [1, 2, 3]
    println(s.size)                                     // 3
    println(s.contains(2))                              // true
    println(s.contains(9))                              // false
    println(s.first())                                  // 1
    println(s.last())                                   // 3
    println(s.lower(2))                                 // 1
    println(s.floor(2))                                 // 2
    println(s.ceiling(2))                               // 2
    println(s.higher(2))                                // 3
    println(s.pollFirst())                              // 1
    println(s.pollLast())                               // 3
    println(s)                                          // [2]
    s.add(5)
    s.add(4)
    println(s.descendingSet())                          // [5, 4, 2]
    println(s.subSet(2, 5))                             // [2, 4]
    println(s.headSet(4))                               // [2]
    println(s.tailSet(4))                               // [4, 5]
    println(s.comparator())                             // null
    val it = s.descendingIterator()
    val seen = ArrayList<Int>()
    while (it.hasNext()) seen.add(it.next())
    println(seen)                                       // [5, 4, 2]
    println(s is NavigableSet<*>)                       // true
    println(s is SortedSet<*>)                          // true

    // Null elements are rejected.
    val ns = ConcurrentSkipListSet<Int?>()
    try {
        ns.add(null)
        println("no-throw")
    } catch (e: NullPointerException) {
        println("npe-add")                              // npe-add
    }
    try {
        println(ns.contains(null))
    } catch (e: NullPointerException) {
        println("npe-contains")                         // npe-contains
    }
    try {
        ns.remove(null)
        println("no-throw")
    } catch (e: NullPointerException) {
        println("npe-remove")                           // npe-remove
    }
    try {
        ConcurrentSkipListSet<Int?>(listOf(7, null))
        println("no-throw")
    } catch (e: NullPointerException) {
        println("npe-ctor")                             // npe-ctor
    }
    try {
        ns.addAll(listOf(1, null))
        println("no-throw")
    } catch (e: NullPointerException) {
        println("npe-addAll")                           // npe-addAll
    }
    println(ns)                                         // [1] — partial add stays

    // Constructors: collection sort, comparator, SortedSet comparator reuse.
    println(ConcurrentSkipListSet(listOf(3, 1, 2)))     // [1, 2, 3]
    val desc = TreeSet<String>(compareByDescending { it })
    desc.add("a")
    desc.add("b")
    println(ConcurrentSkipListSet(desc))                // [b, a]
    val byLen = ConcurrentSkipListSet<String>(compareBy { it.length })
    byLen.add("ccc")
    byLen.add("a")
    byLen.add("bb")
    println(byLen)                                      // [a, bb, ccc]
    println(s.clone())                                  // [2, 4, 5]
    println(s.clone() == s)                             // true

    // --- ConcurrentSkipListMap ---
    val m = ConcurrentSkipListMap<Int, String>()
    println(m.put(2, "b"))                              // null
    m.put(1, "a")
    m.put(3, "c")
    println(m[4])                                       // null
    println(m)                                          // {1=a, 2=b, 3=c}
    println(m.size)                                     // 3
    println(m[2])                                       // b
    println(m.containsKey(3))                           // true
    println(m.containsValue("c"))                       // true
    println(m.firstKey())                               // 1
    println(m.lastKey())                                // 3
    println(m.lowerKey(2))                              // 1
    println(m.floorKey(2))                              // 2
    println(m.ceilingKey(2))                            // 2
    println(m.higherKey(2))                             // 3
    val fe = m.firstEntry()
    println("${fe?.key}=${fe?.value}")                  // 1=a
    val le = m.lastEntry()
    println("${le?.key}=${le?.value}")                  // 3=c
    println(m.descendingMap())                          // {3=c, 2=b, 1=a}
    println(m.descendingKeySet())                       // [3, 2, 1]
    println(m.subMap(1, 3))                             // {1=a, 2=b}
    println(m.headMap(2))                               // {1=a}
    println(m.tailMap(2))                               // {2=b, 3=c}
    println(m.putIfAbsent(2, "B"))                      // b
    println(m.putIfAbsent(4, "d"))                      // null
    println(m.remove(2, "x"))                           // false
    println(m.remove(2, "b"))                           // true
    println(m.replace(3, "c", "C"))                     // true
    println(m.replace(9, "z"))                          // null
    println(m.replace(3, "C2"))                         // C
    println(m.getOrDefault(3, "?"))                     // C2
    println(m.getOrDefault(9, "?"))                     // ?
    println(m)                                          // {1=a, 3=C2, 4=d}
    val pf = m.pollFirstEntry()
    println("${pf?.key}=${pf?.value}")                  // 1=a
    val pl = m.pollLastEntry()
    println("${pl?.key}=${pl?.value}")                  // 4=d
    println(m)                                          // {3=C2}
    println(m is ConcurrentMap<*, *>)                   // true
    println(m is ConcurrentNavigableMap<*, *>)          // true
    println(m is NavigableMap<*, *>)                    // true

    // Null keys and values are rejected.
    val nm = ConcurrentSkipListMap<Int?, String?>()
    try {
        nm.put(null, "x")
        println("no-throw")
    } catch (e: NullPointerException) {
        println("npe-put-key")                          // npe-put-key
    }
    try {
        nm.put(1, null)
        println("no-throw")
    } catch (e: NullPointerException) {
        println("npe-put-val")                          // npe-put-val
    }
    try {
        nm.get(null)
        println("no-throw")
    } catch (e: NullPointerException) {
        println("npe-get")                              // npe-get
    }
    try {
        nm.containsKey(null)
        println("no-throw")
    } catch (e: NullPointerException) {
        println("npe-containsKey")                      // npe-containsKey
    }
    try {
        nm.remove(null)
        println("no-throw")
    } catch (e: NullPointerException) {
        println("npe-remove-key")                       // npe-remove-key
    }
    println(nm.remove(1, null))                         // false
    try {
        nm.putIfAbsent(1, null)
        println("no-throw")
    } catch (e: NullPointerException) {
        println("npe-putIfAbsent")                      // npe-putIfAbsent
    }
    try {
        nm.containsValue(null)
        println("no-throw")
    } catch (e: NullPointerException) {
        println("npe-containsValue")                    // npe-containsValue
    }
    println(nm)                                         // {}

    // Constructors: Map sorts naturally, SortedMap keeps its comparator.
    println(ConcurrentSkipListMap(mapOf(5 to "e", 4 to "d")))  // {4=d, 5=e}
    val sm = TreeMap<String, Int>(compareByDescending { it })
    sm["x"] = 1
    sm["y"] = 2
    val m4 = ConcurrentSkipListMap(sm)
    println(m4)                                         // {y=2, x=1}
    println(m4.comparator() == sm.comparator())         // true
    println(m.clone())                                  // {3=C2}
    println(m.isEmpty())                                // false
}
