// KUU-2580: member-extension delegates resolve inside a generic apply receiver lambda.
class A { var x: String = "Fail" }

class C {
    var A.y: String by A::x

    fun setAndRead(a: A): String {
        a.y = "OK"
        return a.y
    }
}

fun box(): String {
    val a = A()
    C().apply {
        a.y = "OK"
        return a.y
    }
}

fun main() {
    println(box())
    println(C().setAndRead(A()))
}
