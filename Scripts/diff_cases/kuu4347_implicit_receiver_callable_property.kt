// KUU-4347: an implicit receiver's member callable property sits on a nearer
// call-tower level than package/import scope functions, so `apply()` binds
// the property — not `kotlin.apply` — even though the scope candidate
// resolves. Regression: KSwiftK reported SEMA-0480 ("No value passed for
// parameter 'block'") inside `with` lambdas.
class Outer {
    val apply: () -> Int = { 7 }
    fun viaThis(): Int = apply()
}

fun main() {
    println(with(Outer()) { apply() })
    println(Outer().viaThis())
}
