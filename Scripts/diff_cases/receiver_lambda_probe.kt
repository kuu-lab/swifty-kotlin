fun probe(): Int.() -> String = { "OK" }

fun box(): String {
    val f = probe()
    return 1.f()
}

fun main() {
    println(box())
}
