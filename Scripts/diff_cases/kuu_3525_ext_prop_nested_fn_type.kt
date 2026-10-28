// KUU-3525 regression for the JetBrains propertyWithExtensionNestedType fixture.
// Source: https://github.com/JetBrains/kotlin/blob/master/compiler/testData/codegen/box/extensionProperties/propertyWithExtensionNestedType.kt
// A top-level property typed `A.(A.() -> String) -> String` must be invocable
// through receiver-call sugar, including the trailing-lambda form that carries
// no `()` and therefore sets no explicit-call marker.
class A(val a: String)

val x : A.(A.() -> String) -> String = { lambda: A.()-> String ->
    A("OK").lambda()
}

fun main() {
    println(A("FAIL").x { this.a })
}
