// DIFF_CANDIDATE_ONLY
// KUU-4374: KClass.primaryConstructor / constructors handles are bare
// RuntimeKConstructorBox objects that must render JVM-style
// `fun `<init>`(P): C` signatures, not `<object 0x…>`.
// Candidate-only: JVM kotlin-reflect needs `kotlin.reflect.full` imports and
// reports a different constructor/member surface, so byte parity is only
// pinnable on the candidate side.

import kotlin.reflect.full.*

class C(val x: Int) {
    fun df(a: Int): Int = a + x
}

fun main() {
    println(C::class.primaryConstructor)
    println(C::class.constructors)
    println(C::x.toString())
    println(C::class.constructors.first().name)
    println(C::df)
}
