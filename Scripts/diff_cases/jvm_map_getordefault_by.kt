// DIFF_JVM
// Map.getOrDefault dispatches to the JDK default method, and `by map`
// delegation resolves property names through getOrImplicitDefaultNullable.
fun main() {
    val m = mapOf("v" to 5, "x" to 9)
    println(m.getOrDefault("zz", -1))
    println(m.getOrDefault("v", -1))
    val v: Int by m
    val x: Int by m
    println(v + x)
}
