// KUU-3144: A `{ }` block on the line after a bare value (here `Unit`) is a
// new statement, not a trailing lambda on that value. kotlinc reports
// "lambda expression is never invoked" as a warning only; KSwiftK previously
// bound it as a call argument and failed with KSWIFTK-SEMA-0023
// "Unresolved function 'Unit'".
fun box(): String {
    val tmp = Unit
    {}
    return "OK"
}

// Control shapes that do bind a next-line `{ }`:
// - a call's argument list ends in `)` (`run()` + `{ }` invokes run { })
// - a type-argument list ends in `>` (`id<Int>` + `{ }` invokes id<Int> { })
// - a declaration/literal header awaits its body (`fun f(): Int`,
//   `object : I`, `class C`).
fun takeBlock(block: () -> String): String {
    return block()
}

fun callTail(): String {
    takeBlock()
        { "OK" }
    return "OK"
}

fun <T> idGeneric(block: () -> T): T = block()

fun typeArgTail(): String {
    idGeneric<String>
        { "OK" }
    return "OK"
}

interface Listener { fun value(): String }

fun headersBindTheirBody(): String {
    fun local(): String
    { return "OK" }
    val o = object : Listener
    { override fun value() = "OK" }
    return local() + o.value()
}

// Non-binding controls: name tails, indexed tails, parenthesized and `!!`
// tails are complete expressions, so the `{ }` is a separate statement.
fun nonBindingControls(): String {
    val f: () -> String = { "OK" }
    f
    { "unused" }
    val xs = listOf({ "OK" })
    xs[0]
    { "unused" }
    (f)
    { "unused" }
    return f() + xs[0]()
}

fun main() {
    println(box())
    println(callTail())
    println(typeArgTail())
    println(headersBindTheirBody())
    println(nonBindingControls())
}
