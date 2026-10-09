fun <T> collect(builderAction: MutableList<T>.() -> Unit): List<T> = buildList<T>(builderAction)

fun demo(): Int {
    val xs = collect { add(1); add(2) }
    return xs[0]
}

fun main() {
    println(demo())
}
