// MutableMap.keys/.values must be live views over the map, not snapshots
// taken at access time (MutableMap.entries was already live).
fun main() {
    val m = mutableMapOf(1 to "a")
    val ks = m.keys; val vs = m.values; val es = m.entries
    m[2] = "b"
    println(ks); println(vs); println(es.size)
    m.remove(1)
    println(ks); println(vs.toList())
}
