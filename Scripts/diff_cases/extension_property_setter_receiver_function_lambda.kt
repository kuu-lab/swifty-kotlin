// KUU-2456 regression for the Kotlin 2.3.10 extensionProperyWithExtensionType fixture.
// Source: https://github.com/JetBrains/kotlin/blob/679366a83f99851b42f64795f10ed803ff011c73/compiler/testData/codegen/box/extensionProperties/extensionProperyWithExtensionType.kt
// Pinned fixture blob: c1195a441b30c5e0764fefe7d3cb0c4b6011d35d; SHA-256: 1ac07561ac344fd5eb9ba5d581cbd20809a412ecedbd722d5ff732ae709a468d.
var <T> T.varProp: T.()-> String
    get() = { "1" }
    set(value: T.()-> String) {}

var Int.intProp: Int.(String)-> String
    get() = { y: String -> y }
    set(value: Int.(String) -> String) { }

fun test(){
    val funFromVarProp = 1.varProp
    funFromVarProp(1)
    1.funFromVarProp()
    1.varProp = { "2" }

    val funFromIntProp = 1.intProp
    funFromIntProp(1, "")
    1.funFromIntProp("")
    1.intProp = { y: String -> y }
}

fun box(): String {
    test()
    return "OK"
}

var Int.ordinaryProp: (String) -> String
    get() = { it }
    set(value) {}

var Number.overloadedProp: (Boolean) -> Boolean
    get() = { it }
    set(value) {}

var Int.overloadedProp: (String) -> String
    get() = { it }
    set(value) {}

fun setterControls() {
    1.ordinaryProp = { it }
    1.overloadedProp = { value: String -> value }

    val typed: Int.(String) -> String = { value: String -> value }
    1.intProp = typed

    var local: Int.(String) -> String = { value: String -> value }
    local = { value: String -> value }
}

fun main() {
    setterControls()
    println(box())
}
