// KUU-2252: qualified-name control for the private nested classifier case.
package p

class A {
    private class B { class D }

    fun make(): String {
        B.D()
        return "OK"
    }
}

fun box(): String = A().make()

fun main() {
    println(box())
}
