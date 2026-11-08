// KUU-4500: java.util.LinkedHashMap's (initialCapacity, loadFactor,
// accessOrder) constructor. accessOrder=true turns get/put into LRU-order
// touches; iteration/views reflect the resulting order.
fun dump(m: Map<String, Int>): String = m.entries.joinToString(",") { "${it.key}=${it.value}" }

fun main() {
    val m = LinkedHashMap<String, Int>(16, 0.75f, true)
    m["a"] = 1
    m["b"] = 2
    m["c"] = 3
    m["d"] = 4
    println(dump(m)) // a=1,b=2,c=3,d=4
    println(m["b"]) // get counts as an access
    println(dump(m)) // a=1,c=3,d=4,b=2
    m["a"] = 10 // put on an existing key also moves it to the tail
    println(dump(m)) // c=3,d=4,b=2,a=10
    println(m.containsKey("c")) // containsKey is not an access
    println(dump(m)) // c=3,d=4,b=2,a=10
    println(m.getOrElse("c") { -1 }) // delegates to get
    println(dump(m)) // d=4,b=2,a=10,c=3
    m["e"] = 5
    println(dump(m)) // d=4,b=2,a=10,c=3,e=5
    m.remove("b") // removal is not an access
    println(dump(m)) // d=4,a=10,c=3,e=5
    println(m.getOrDefault("missing", 99))
    println(dump(m)) // d=4,a=10,c=3,e=5
    println(m.getOrDefault("d", 99)) // hit: getOrDefault counts as an access
    println(dump(m)) // a=10,c=3,e=5,d=4
    println(m.getOrPut("f") { 6 }) // miss: get + put
    println(m.getOrPut("c") { -1 }) // hit: get counts as an access
    println(dump(m)) // a=10,e=5,d=4,f=6,c=3
    println(m.keys)
    println(m.values)
    println(m.toString())
    for ((k, v) in m) {
        print("$k$v;")
    }
    println()

    // accessOrder=false keeps insertion order regardless of access.
    val n = LinkedHashMap<String, Int>(16, 0.75f, false)
    n["x"] = 1
    n["y"] = 2
    n["z"] = 3
    println(n["x"])
    println(dump(n)) // x=1,y=2,z=3

    // The two-argument form defaults accessOrder to false.
    val p = LinkedHashMap<String, Int>(16, 0.75f)
    p["x"] = 1
    p["y"] = 2
    println(p["x"])
    println(dump(p)) // x=1,y=2

    // Map.Entry.value reads are not accesses on the JVM.
    val e = LinkedHashMap<String, Int>(16, 0.75f, true)
    e["u"] = 7
    e["v"] = 8
    e["w"] = 9
    println(e.entries.first().value)
    println(dump(e)) // u=7,v=8,w=9 — entry.value did not reorder

    // MutableEntry.setValue writes the node in place on the JVM (HashMap
    // .Node.setValue) and does NOT count as an access.
    e.entries.first().setValue(70)
    println(dump(e)) // u=70,v=8,w=9
}
