// KUU-3145 regression for the JetBrains propertyWithExtensionNestedType fixture.
// Source: https://github.com/JetBrains/kotlin/blob/master/compiler/testData/codegen/box/extensionProperties/propertyWithExtensionNestedType.kt
// A package-scope property whose value has receiver-function type
// `A.(A.() -> String) -> String` must be invocable through the
// `receiver.name { }` member-call sugar, binding the explicit receiver as the
// function type's extension receiver. The trailing-lambda gate itself is
// pinned by kuu_3525_ext_prop_nested_fn_type.kt (KUU-3525, #11673); this case
// also covers the shadowed form, where an inapplicable member named `x`
// collects candidates but cannot accept the lambda, so the package-scope
// property's invoke convention must still win (KUU-3145).
open class A(val a: String)

class C(val c: String) : A(c) {
    fun x(i: Int): String = "member"
}

val x: A.(A.() -> String) -> String = { lambda: A.() -> String ->
    A("OK").lambda()
}

fun box(): String {
    return A("FAIL").x { this.a }
}

fun boxShadowed(): String {
    return C("FAIL").x { this.a }
}

fun main() {
    println(box())
    println(boxShadowed())
}
