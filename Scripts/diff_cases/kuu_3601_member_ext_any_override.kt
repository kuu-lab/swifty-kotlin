// KUU-3601: member extension functions declared inside an interface or class
// never hide kotlin.Any members — members always win over extensions, so no
// `override` modifier is required. A false KSWIFTK-SEMA-OVERRIDE diagnostic
// used to reject this. Minimized from JetBrains testData
// codegen/box/extensionFunctions/memberExtensionEqualsHashCodeToStringInInterface.kt.
interface AssertDSL {
    infix fun Any?.equals(other: Any?) {
        if (this != other) throw AssertionError("$this != $other")
    }

    fun Any?.toString(): String = ""
    fun Any?.hashCode(): Int = 0
}

class C(val x: Int) : AssertDSL

fun C.test(): String {
    x equals 42
    null.toString()
    null.hashCode()
    return "OK"
}

fun box(): String = C(42).test()

fun main() {
    println(box())
}
