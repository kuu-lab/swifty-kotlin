open class Outer(val fn: (() -> String)?) {
    companion object { val ok = "OK" }
    val ok = "Fail: Outer.ok"
    inner class Inner : Outer({ ok })
}

open class Base(val v: String)
class Derived(p: String) : Base(p + helper) {
    companion object { const val helper = "!" }
}

fun main() {
    println(Outer(null).Inner().fn?.invoke()!!)
    println(Derived("a").v)
}
