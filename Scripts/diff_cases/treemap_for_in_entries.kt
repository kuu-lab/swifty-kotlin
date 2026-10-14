import java.util.TreeMap

fun main() {
    val tree = TreeMap<String, Int>()
    tree["b"] = 2
    tree["a"] = 1
    for (e in tree) println(e)
    for ((k, v) in tree) println("$k=$v")
    for (e in tree) println(e.key + e.value)
    val sorted: java.util.SortedMap<String, Int> = tree
    for (e in sorted) println(e.key)
}
