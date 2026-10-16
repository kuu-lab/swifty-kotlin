fun <T> use(value: T): String = "OK"

class TopLevel

fun box(): String {
    class Local
    val inferred = use(Local())
    val explicit = use<Local>(Local())
    val topLevel = use(TopLevel())
    val widened: Any = Local()
    return if (inferred == "OK" && explicit == "OK" && topLevel == "OK" && widened is Any) "OK" else "FAIL"
}

class Q<TT> {
    fun <T> qz(x: T, block: (T) -> String) = block(x)

    fun problematic(): String {
        class CC
        return qz(CC::class) { "OK" }
    }
}

fun main() {
    println(box())
    println(Q<Int>().problematic())
}
