// KSWIFTK-SEMA-0002 regression: an extension-function-typed value
// (`Int.(Int) -> Int`) rejected a bare call with the receiver passed as an
// ordinary leading positional argument (`ef(3, 4)`), even though
// receiver-dot-call sugar (`1.ef(2)`) and the ambient-receiver form (calling
// it bare inside a receiver scope, e.g. `with(10) { ef(5) }`) already
// worked. Both forms must keep working side by side.
fun main() {
    val ef: Int.(Int) -> Int = { this + it }
    println(1.ef(2))
    println(ef(3, 4))

    val sf: String.() -> Int = { length }
    println(sf("hello"))

    with(10) {
        println(ef(3, 4))
        println(ef(5))
    }
}
