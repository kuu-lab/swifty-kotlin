// KUU-3131: `map[key] += value` on MutableMap receivers must resolve the
// `MutableMap<K, V>.set` extension for the write-back half of the compound
// assignment; the `get` element type (V?) is nullable, so the result type fed
// into `set` has to keep K/V substituted from the concrete receiver.
// Pinned upstream program:
// https://github.com/JetBrains/kotlin/blob/679366a83f/compiler/testData/codegen/box/operatorConventions/kt14227.kt
fun main() {
    val m = HashMap<String, String>()
    m["a"] = "A"
    m["a"] += "B"
    println(m["a"])

    val viaInterface: MutableMap<String, String> = HashMap()
    viaInterface["x"] = "1"
    viaInterface["x"] += "2"
    println(viaInterface["x"])

    val factory: MutableMap<String, String> = mutableMapOf()
    factory["k"] = "p"
    factory["k"] += "q"
    println(factory["k"])

    val linked = LinkedHashMap<String, String>()
    linked["z"] = "L"
    linked["z"] += "M"
    println(linked["z"])
}
