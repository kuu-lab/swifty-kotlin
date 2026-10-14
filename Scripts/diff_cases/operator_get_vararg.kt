// KUU-2076: Indexed operator calls must pass the normalized vararg array.
operator fun String.get(vararg v: Any) = "OK"

fun main() {
    println("foo"[44, "x"])
}
