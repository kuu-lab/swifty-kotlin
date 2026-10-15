// KUU-2252: minimal private nested classifier star-import reproducer.
package p

import p.A.B.*

class A {
    private class B { class D }

    fun make(): String {
        D()
        return "OK"
    }
}

fun box(): String = A().make()

fun main() {
    println(box())
}
