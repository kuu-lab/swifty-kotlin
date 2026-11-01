// Regression (KUU-3781): an expression-bodied anonymous function carrying a
// `context(...)` prefix and/or an extension receiver parses and evaluates
// like its block-bodied form. kswiftc previously rejected it with
// KSWIFTK-PARSE-0001 "Expected '{' for anonymous function body." while
// kotlinc accepts the same syntax.

fun main() {
    val f = context(a: String) fun () = a
    val g = context(a: String) fun String.() = this + a
    val h = fun String.() = this + "!"

    val direct = f("O")
    val viaWith = with("") { "K".g() }
    val plain = "K".h()
    println(direct + viaWith + plain)
}
