import java.util.concurrent.ConcurrentHashMap

fun main() {
    val m = ConcurrentHashMap<String, Int>()
    m.putIfAbsent("a", 1)
    m.putIfAbsent("a", 2)
    m.replace("a", 9)
    m.putIfAbsent("b", 3)
    println(m["a"])
    println(m["b"])
    val kept = m.putIfAbsent("a", 7)
    println(kept)
    for (i in 1..2) {
        m.putIfAbsent("c", i)
    }
    println(m["c"])
}
