// KUU-2024: an unrelated receiver must not hide the default-imported operator.
class Counter
operator fun Counter.plusAssign(value: Int) {}
fun main() {
    val scope = mutableMapOf<String, Boolean>()
    scope += "x" to true
    println(scope["x"])
}
