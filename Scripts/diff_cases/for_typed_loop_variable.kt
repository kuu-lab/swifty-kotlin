// DIFF_JVM
// Explicitly typed for-loop variables (`for (x: T in xs)`): kotlinc accepts
// them and Sema checks T against the iterator element type. The JVM source
// grammar used to reject the annotation outright (KSWIFTK-JVM-0001).
fun main() {
    for (s: String in listOf("a", "bb", "ccc")) {
        println("${s.length}:${s}")
    }
    for (n: Long? in listOf(1L, null, 3L)) {
        println(n)
    }
    for (pair: Pair<String, Int> in listOf("x" to 1, "yy" to 22)) {
        println("${pair.first}${pair.second}")
    }
    for (entry: Map.Entry<String, Int> in mapOf("k" to 7).entries) {
        println(entry.key + entry.value)
    }
    for ((k, v) in mapOf("a" to 1, "b" to 2)) {
        for (ch: Char in k) {
            print("$ch$v ")
        }
    }
    println()
    for (d: Double in doubleArrayOf(1.5, 2.5)) {
        println(d * 2)
    }
    // A declared reference supertype keeps one box per iteration, so
    // referential identity holds like kotlinc (`x === x` is true).
    for (x: Any in doubleArrayOf(1.0, 2.0)) {
        println(x === x)
    }
    for (n: Number in intArrayOf(1, 2)) {
        println(n === n)
    }
}
