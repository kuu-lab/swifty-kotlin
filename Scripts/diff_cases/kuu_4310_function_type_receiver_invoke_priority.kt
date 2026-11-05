// KUU-4310: an unqualified `invoke(args)` on a function-typed implicit
// receiver is `this.invoke(args)` — the receiver-tier member beats an
// applicable package-scope `invoke` (kotlinc resolves `r` to `Unit`; binding
// the scope `invoke(Int): String` instead makes `val check: Unit = r` fail).
package b

fun invoke(x: Int): String = "scope:$x"
fun invoke(x: String): String = "scope-str:$x"

fun ((Int) -> Unit).callIt() {
    val r = invoke(5)
    val check: Unit = r
}

fun ((Int) -> Unit).callOutOfTower() {
    // `this.invoke` takes Int, so `invoke("x")` continues the tower outward
    // and the scope `invoke(String): String` wins.
    println(invoke("x"))
}

fun main() {
    val f: (Int) -> Unit = { println("fn:$it") }
    f.callIt()
    f.callOutOfTower()
}
