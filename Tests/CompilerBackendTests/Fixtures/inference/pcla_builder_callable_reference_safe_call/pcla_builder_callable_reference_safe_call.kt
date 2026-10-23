@OptIn(ExperimentalStdlibApi::class)
fun test(s: String?): Int {
    val list = buildList {
        s?.let(::add)
    }
    return list.size
}

fun box(): String {
    return when (test("hello")) {
        1 -> "OK"
        else -> "Error"
    }
}

fun main() {
    println(box())
}
