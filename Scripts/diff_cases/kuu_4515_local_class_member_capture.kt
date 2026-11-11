// DIFF_JVM
fun main() {
    val m = mapOf("k" to 5)
    class P(val name: String) { operator fun getValue(r: Any?, p: Any): Int = m.getValue(name) }
    val v: Int by P("k")
    println(v)
}
