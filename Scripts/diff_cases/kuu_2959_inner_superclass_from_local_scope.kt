// KUU-2959: subclassing an inner class from object/local/extension scope must
// still pass the implicit outer instance to the inherited `$outer` field.
// Regression coverage for the JetBrains innerNested/superConstructorCall and
// super/superConstructor suites.

open class K2959Father(val param: String) {
    abstract inner class InClass {
        fun work(): String = param
    }

    inner class Child(p: String) : K2959Father(p) {
        inner class PrimaryChild2 : K2959Father.InClass()

        inner class SecondaryChild2 : K2959Father.InClass {
            constructor() : super()
        }

        fun test(): InClass {
            class LocalSub : K2959Father.InClass()
            return LocalSub()
        }
    }
}

class K2959Outer(val outer: String) {
    open inner class Inner(val inner: String) {
        constructor() : this("K")

        fun test() = outer + inner
    }

    fun obj(): Inner = object : Inner() {}
}

fun K2959Outer.extSub(u: String, v: String, w: String): K2959Outer.Inner {
    class ExtSub(z: String) : K2959Outer.Inner("$z$v$w")
    return ExtSub(u)
}

fun innerViaSecondaryCtor(): String =
    K2959Father("fail").Child("OK").SecondaryChild2().work()

fun innerViaPrimaryCtor(): String =
    K2959Father("fail").Child("OK").PrimaryChild2().work()

fun localSubclassOfInner(): String =
    K2959Father("fail").Child("OK").test().work()

fun objectWithDelegatingCtor(): String = K2959Outer("O").obj().test()

fun objectInsideLocalClassCapture(): String {
    val capture = "oh"

    class Local {
        val captured = capture

        open inner class Inner(val d: Double = -1.0, val s: String, vararg val y: Int) {
            open fun result() = "Fail"
        }

        val obj = object : Inner(s = "OK") {
            override fun result() = s
        }
    }

    return Local().obj.result()
}

fun objectInsideLocalClassBothCaptures(): String {
    val capture = "O"

    class Local {
        val captured = capture

        open inner class Inner(val d: Double = -1.0, val s: String, vararg val y: Int) {
            open fun result() = "Fail"
        }

        val obj = object : Inner(s = "K") {
            override fun result() = capture + s
        }
    }

    return Local().obj.result()
}

fun objectSubclassOfLocalClosure(): String {
    val d = 42.0
    val c = 'C'

    open class Local(val l: Long) {
        fun foo(): Boolean = d == 42.0 && c == 'C' && l == 239L
    }

    if (object : Local(239L) {
        fun bar(): Boolean = foo()
    }.bar()) {
        return "OK"
    }

    return "Fail"
}

fun subclassInExtensionFunction(): String {
    val r = K2959Outer("1").extSub("2", "3", "4").test()
    return if (r == "1234") "OK" else "fail: $r"
}

fun main() {
    println(innerViaSecondaryCtor())
    println(innerViaPrimaryCtor())
    println(localSubclassOfInner())
    println(objectWithDelegatingCtor())
    println(objectInsideLocalClassCapture())
    println(objectInsideLocalClassBothCaptures())
    println(objectSubclassOfLocalClosure())
    println(subclassInExtensionFunction())
}
