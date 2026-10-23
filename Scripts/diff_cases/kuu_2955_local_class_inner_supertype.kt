// KUU-2955: a local class extending an inner class through an extension
// receiver must initialize the inherited `$outer` link. Based on JetBrains
// localClasses/subclassingExtensionReceiverClass.
class A(val x: String) {
    open inner class AB(val y: String) {
        fun bar() = x + y
    }
}

fun A.foo(u: String, v: String, w: String): A.AB {
    class FooC(z: String) : A.AB("$z$v$w")
    return FooC(u)
}

fun box(): String {
    val r = A("1").foo("2", "3", "4").bar()
    if (r != "1234") return "fail: $r"
    return "OK"
}

fun memberPath(): String {
    class A2(val x: String) {
        open inner class AB(val y: String) {
            fun bar() = x + y
        }
        fun foo(u: String, v: String): AB {
            class FooC(z: String) : AB("$z$v")
            return FooC(u)
        }
    }
    return A2("a").foo("b", "c").bar()
}

fun main() {
    println(box())
    println(memberPath())
}
