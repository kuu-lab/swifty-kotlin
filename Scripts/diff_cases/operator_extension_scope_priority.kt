// KUU-2024: applicable package and member operators retain their priority.
class Counter {
    operator fun plusAssign(value: Int) { println("member: $value") }
}
operator fun Counter.plusAssign(value: Int) { println("extension: $value") }
operator fun MutableMap<String, Boolean>.plusAssign(value: Pair<String, Boolean>) {
    println("user: ${value.first}")
    put(value.first, value.second)
}
fun main() {
    val counter = Counter()
    counter += 2
    val scope = mutableMapOf<String, Boolean>()
    scope += "x" to true
    println(scope["x"])
}
