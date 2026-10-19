fun probe(): Int.() -> String = fun Int.(): String { return "OK" }

fun box(): String {
    val f = probe()
    return 1.f()
}

fun main() {
    println(box())
}
