package kuu2460.minimal

fun box(): String {
    val f: Function1<Any?, *> = { "OK" }
    return f("OK") as String
}
