fun f(idx: Int?) = idx?.let { "abcd".get(it) }

fun main() {
    println(f(2))
    println(f(null))
}
