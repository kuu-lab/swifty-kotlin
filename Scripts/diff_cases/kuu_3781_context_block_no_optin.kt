// Regression (KUU-3781): calling the stdlib `context(...) { }` scope
// function and `contextOf()` must not require
// @OptIn(ExperimentalContextParameters). kotlin-stdlib 2.4.20 carries no
// marker on these overloads; kswiftc's bundled copy still did and reported
// KSWIFTK-SEMA-OPT-IN on every `context(...) { }` call.

fun main() {
    val out = context("O") {
        contextOf<String>() + "K"
    }
    println(out)
}
