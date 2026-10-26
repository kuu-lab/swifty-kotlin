class V {
    fun target(x: String = "x", y: String = "y", z: String = "z") = x + y + z
}

fun captureOne(f: (V, String, String) -> String): Any = f
fun captureAll(f: (V) -> String): Any = f
fun captureFull(f: (V, String, String, String) -> String): Any = f

fun main() {
    println(captureOne(V::target) == captureOne(V::target))
    println(captureAll(V::target) == captureAll(V::target))
    println(captureFull(V::target) == captureFull(V::target))
}
