class A {
    class B {
        fun direct(): Boolean = true
    }
}

class Plain

fun A.B.test(): Boolean = true
fun Plain.test(): Boolean = true

fun takeExtension(f: A.B.() -> Boolean): Boolean = f(A.B())
fun takeFunction(f: (A.B) -> Boolean): Boolean = f(A.B())
fun takePlain(f: (Plain) -> Boolean): Boolean = f(Plain())
fun takeBound(f: () -> Boolean): Boolean = f()

fun box(): String {
    val passed = takeExtension(A.B::test)
        && takeFunction(A.B::test)
        && takeFunction(A.B::direct)
        && takePlain(Plain::test)
        && takeBound(A.B()::test)
    return if (passed) "OK" else "FAIL"
}

fun main() {
    println(box())
}
