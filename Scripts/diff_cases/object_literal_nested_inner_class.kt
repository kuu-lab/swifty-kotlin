// Nested inner classes in anonymous objects are available to earlier property initializers.
fun box(): String {
    return object {
        val a = A("OK")
        inner class A(val ok: String)
    }.a.ok
}

fun declarationOrderReversed(): String {
    return object {
        inner class A(val ok: String)
        val a = A("OK")
    }.a.ok
}

fun anonymousPropertyControl(): String = object { val value = "OK" }.value

class NamedOuter {
    val a = A("OK")
    inner class A(val ok: String)
}

fun namedClassControl(): String = NamedOuter().a.ok

fun innerClassOuterReceiverAndGetter(): String {
    val anonymous = object {
        val outerValue = "OUTER"
        val a = A("OK")
        inner class A(val ok: String) {
            val initializedValue = ok
            val throughGetter: String
                get() = initializedValue
            fun outerValueFromInner(): String = outerValue
        }
    }
    return anonymous.a.ok + ":" + anonymous.a.throughGetter + ":" + anonymous.a.outerValueFromInner()
}

fun main() {
    println(box())
    println(declarationOrderReversed())
    println(anonymousPropertyControl())
    println(namedClassControl())
    println(innerClassOuterReceiverAndGetter())
}
