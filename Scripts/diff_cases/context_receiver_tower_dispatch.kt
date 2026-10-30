// Regression: member scope resolution stopped at the lexical scope tier, so a
// nearer implicit receiver's member lost to a farther tower entry's member
// (KUU-3170, dispatchExtensionAndContextReceiverResolve).
class A {
    context(a: String)
    fun test1(): String = "A.test1 "

    fun String.test2(): String = "A.test2 "

    fun OnlyDispatch.usage(): String =
        with("") { test1() } + with("") { test2() }

    fun Extension.usage(): String =
        with("") { test1() }
}

class OnlyDispatch {
    fun test1(): String = "OnlyDispatch.test1 "
    fun test2(): String = "OnlyDispatch.test2 "
}

class Extension {
    fun String.test1(): String = "Extension.test1 "
}

fun main() {
    with(A()) {
        with(OnlyDispatch()) { println(usage()) }
        with(Extension()) { println(usage()) }
    }
}
