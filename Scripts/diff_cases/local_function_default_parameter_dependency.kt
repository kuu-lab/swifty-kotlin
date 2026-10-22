// DIFF_JVM
fun foo(): String {
    fun bar(x: String, y: String = x): String {
        return y
    }

    return bar("OK")
}

fun box(): String {
    return foo()
}

fun topLevel(x: String, y: String = x): String = y

class Holder {
    fun member(x: String, y: String = x): String = y
}

fun main() {
    println(box())

    fun literal(value: String, suffix: String = "!"): String = value + suffix
    println(literal("literal"))
    println(literal("ignored", "explicit"))

    println(topLevel("top"))
    println(Holder().member("member"))
}
