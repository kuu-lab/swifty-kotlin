// KUU-3175: SAM adapters built from property callable references must
// implement the context-parameter method, and anonymous object literals
// whose members carry a `context(...)` clause must register itable entries.

class C(var a: String) {
    fun foo(): String { return a }
    fun combine(extra: String): String = a + extra
}

fun interface SamInterface {
    context(i: C)
    fun accept(): String
}

val C.extensionProperty: String
    get() = this.foo()

val samObject = SamInterface(C::extensionProperty)

interface CtxInterface {
    context(i: C)
    fun accept(): String
}

// `context(i: C)` on its own line is a declaration prefix, not a member —
// it used to detach from `override fun accept()`, drop the literal's
// ObjectDecl, and panic in virtual dispatch.
val multilineObj = object : CtxInterface {
    context(i: C)
    override fun accept(): String = i.a
}

val sameLineObj = object : CtxInterface {
    context(i: C) override fun accept(): String = i.a
}

fun interface SamWithParams {
    context(i: C)
    fun accept(extra: String): String
}

val samWithParams = SamWithParams(C::combine)

// `context(C) () -> String` is `(C) -> String` — a property reference must
// type-check and invoke across the two spellings.
val propAsContextFunction: context(C) () -> String = C::extensionProperty

fun main() {
    with(C("OK")) {
        println(samObject.accept())
        println(multilineObj.accept())
        println(sameLineObj.accept())
        println(samWithParams.accept("!"))
        println(propAsContextFunction())
    }
}
