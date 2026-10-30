import kotlin.reflect.KFunction1

// KUU-3810: a constructor callable reference reports `<init>` as its
// KCallable.name, not the class name, and its toString uses the escaped
// `<init>` signature shape.
class CtorRefA
class CtorRefB(val x: Int)
class CtorRefOuter {
    inner class Inner(val s: String)
}

fun main() {
    println(::CtorRefA.name)
    println(::CtorRefB.name)
    val boundInner: KFunction1<String, CtorRefOuter.Inner> = CtorRefOuter()::Inner
    println(boundInner.name)
    println(::CtorRefA)
    println(::CtorRefB)
    println(boundInner)
    println(CtorRefB::class.constructors.map { it.name })
}
