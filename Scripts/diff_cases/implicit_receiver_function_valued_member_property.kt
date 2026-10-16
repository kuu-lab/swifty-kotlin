class Holder(
    val f: (Int) -> String,
    val receiverF: Int.() -> Int
) {
    fun method(value: Int): String = "member:$value"
}

fun box(): String {
    val holder = Holder(
        { if (it == 3) "OK" else "FAIL" },
        { this }
    )
    val implicit = with(holder) {
        val local = f
        f(3) + ":" + local(3) + ":" + method(3) + ":" + receiverF(4)
    }
    val explicit = holder.f(3)
    return if (implicit == "OK:OK:member:3:4" && explicit == "OK") "OK" else "FAIL"
}

fun main() {
    println(box())
}
