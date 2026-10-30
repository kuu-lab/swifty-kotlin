// KOTLINC_FLAGS: -XXLanguage:+FunctionalTypeWithExtensionAsSupertype
// KUU-3203: a SAM constructor call whose argument is a produced function
// value used to fail with KSWIFTK-SEMA-0023/0024. Covers the upstream
// shapes:
//   callableReference/adaptedReferences/contextTypeWithSam
//   (`SamInterface(::prop.get())`)
//   callableReference/function/extensionFunctionAsASuperTypePassToSAMInterface
//   (`SamInterface((::A)())`)
//   callableReference/function/extensionFunctionWithExtensionInSAMInterface
//   (`SamInterface(receiver::foo)`)
// plus a stored-function-value control for an extension-receiver SAM member.

fun interface SimpleSam {
    fun accept(): String
}

val prop: () -> String = { "prop" }

fun interface ExtSam {
    fun Int.accept(): String
}

class A : Int.() -> String {
    override fun invoke(p1: Int): String {
        return "O"
    }
}

class B : (Int) -> String {
    override fun invoke(p1: Int): String {
        return "K"
    }
}

fun interface NestedExtSam {
    fun (Int.() -> String).accept(): String
}

fun (Int.() -> String).foo(a: Int.() -> String): String {
    return "nested"
}

fun <T> make(): Int.() -> T {
    return { "" as T }
}

fun main() {
    // Property-reference getter call producing a function value.
    println(SimpleSam(::prop.get()).accept())

    // Invoked constructor references producing nominal FunctionN subtypes.
    val a = ExtSam((::A)())
    val b = ExtSam((::B)())
    var result = ""
    with(a) { result += 1.accept() }
    with(b) { result += 2.accept() }
    println(result)

    // Bound callable reference argument.
    val nested = NestedExtSam(make<String>()::foo)
    with(nested) {
        println(make<String>().accept())
    }

    // Stored function value for a SAM member with an extension receiver.
    val f: Int.() -> String = { "v$this" }
    val stored = ExtSam(f)
    with(stored) { println(3.accept()) }
}
