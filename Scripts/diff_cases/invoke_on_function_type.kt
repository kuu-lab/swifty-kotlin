// KSWIFTK-SEMA-0024 regression: explicit `.invoke(...)` member calls on a
// receiver whose own type is a function type have no nominal owner to
// dispatch a member through, so ordinary member lookup always failed with
// "Unresolved member function 'invoke'".
fun main() {
    val f: (Int) -> Int = { it * 2 }
    println(f.invoke(3))

    val ef: Int.(Int) -> Int = { this + it }
    println(ef.invoke(5, 6))

    val fs = mapOf("dbl" to { x: Int -> x * 2 })
    println(fs["dbl"]?.invoke(4))
}
