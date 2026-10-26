data class A(val x: String) {
    val Int.x: Int get() = this
}

fun main() {
    println(A("OK").component1())
}
