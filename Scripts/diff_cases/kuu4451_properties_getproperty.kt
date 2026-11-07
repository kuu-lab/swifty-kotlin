import java.util.*

fun pick(p: Properties, key: String, fallback: String): String = p.getProperty(key) ?: fallback

fun main() {
    val p = Properties()
    p.setProperty("k", "v")
    // Missing key with default: JVM returns the default, not NPE (KUU-4451).
    println(p.getProperty("x", "d"))
    println(p.getProperty("x"))
    println(p.getProperty("k", "d"))
    // Defaults chain: key absent from both maps still yields the default.
    val p3 = Properties()
    val p2 = Properties(p3)
    println(p2.getProperty("x", "d"))
    p3.setProperty("x", "inherited")
    println(p2.getProperty("x", "d"))
    println(p.getOrDefault("x", "d"))
    // Same platform-typed elvis LHS shape on another java.util surface.
    val q = java.util.ArrayDeque<String>()
    val s: String = q.poll() ?: "empty"
    println(s)
    println(pick(p, "x", "fb"))
}
