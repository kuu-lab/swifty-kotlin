fun callExt(f: @ExtensionFunctionType Function2<String, Int, Unit>, s: String, i: Int) {
    s.f(i)
}

fun main() {
    val ext: @ExtensionFunctionType Function2<String, Int, Unit> = { i ->
        println(this + i.toString())
    }
    "num".ext(5)
    "base".ext(7)
    callExt({ j -> println(this + j.toString()) }, "call", 9)
}
