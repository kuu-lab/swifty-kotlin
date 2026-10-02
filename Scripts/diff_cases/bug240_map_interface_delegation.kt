// BUG-240: `Map`/`MutableMap` interface delegation via `by mapOf(...)` was
// broken in two layers — delegated members did not resolve on the class and
// MutableMap put/putAll itable slots were missing from the prebuilt stdlib
// artifact layout, so interface-typed calls silently no-opped.

class ReadOnlyMap : Map<String, Int> by mapOf("k" to 1)
class ReadWriteMap : MutableMap<String, Int> by mutableMapOf("a" to 1)

fun main() {
    val m = ReadOnlyMap()
    println(m.isEmpty())
    println(m.containsKey("k"))
    println(m["k"])
    println(m.size)

    val asMap: Map<String, Int> = m
    println(asMap["k"])

    val cm = ReadWriteMap()
    cm.put("b", 2)
    println(cm.size)
    println(cm["b"])
    cm.remove("a")
    println(cm.size)

    val mm: MutableMap<String, Int> = cm
    mm.put("c", 3)
    println(mm.size)
    println(mm["c"])
    mm.remove("b")
    println(mm.size)
    println(mm.isEmpty())
}
