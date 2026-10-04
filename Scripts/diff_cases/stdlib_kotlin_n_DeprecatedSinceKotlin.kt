package sample

fun describe(x: kotlin.DeprecatedSinceKotlin?): String =
    if (x == null) "ok" else "fail"

fun main() {
    println(describe(null))
}
