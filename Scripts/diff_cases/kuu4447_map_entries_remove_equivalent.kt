// KUU-4447: MutableMap.entries.remove(e) must use Entry equality (key AND
// value), matching contains() — not require the entry object to originate
// from the same map. JVM EntrySet.remove uses matchValue=true.
fun main() {
    val m = mutableMapOf("b" to 3, "c" to 4)
    println(m.entries.remove(m.entries.first { it.key == "b" }))
    println(m)

    // Equivalent entry from a different map removes the pair.
    val foreign = mutableMapOf("c" to 4).entries.first()
    println(m.entries.remove(foreign))
    println(m)

    // Same key, different value must NOT remove.
    val m2 = mutableMapOf("x" to 1)
    val wrongValue = mutableMapOf("x" to 9).entries.first()
    println(m2.entries.remove(wrongValue))
    println(m2)

    // Detached read-only Map.Entry also removes by equality.
    val m3 = mutableMapOf("k" to "v")
    val detached = mapOf("k" to "v").entries.first()
    println(m3.entries.remove(detached))
    println(m3)

    // removeAll driven by a foreign entries set.
    val a = mutableMapOf("p" to 1, "q" to 2)
    val b = mutableMapOf("p" to 1)
    println(a.entries.removeAll(b.entries))
    println(a)
}
