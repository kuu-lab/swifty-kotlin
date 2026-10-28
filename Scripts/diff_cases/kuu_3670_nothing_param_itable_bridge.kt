// KUU-3670: an override narrowing an erased interface parameter to Nothing
// needs an itable bridge that checkcasts the argument — always failing for
// non-null (kotlin/testData/codegen/box/bridges/test24.kt).
interface I<T> {
    fun foo(p: T)
}

class C : I<Nothing> {
    override fun foo(p: Nothing) {
        println(p.toString())
    }
}

fun box(): String {
    val c = C()
    try {
        val x = (c as I<String>).foo("zzz")
        return "FAIL: $x"
    } catch (e: ClassCastException) {
        return "OK"
    }
}

fun main() {
    println(box())
}
