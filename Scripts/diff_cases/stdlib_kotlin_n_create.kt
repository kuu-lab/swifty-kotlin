@Suppress("INVISIBLE_REFERENCE", "INVISIBLE_MEMBER")
fun main() {
    val marker: Any = kotlin.createFailure(RuntimeException("boom"))
    println(marker.toString().length > 0)
}
