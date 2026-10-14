class A {
    class A
    fun A.foo(): String {
        return "OK"
    }
}

fun main() {
    with(A()) {
        println(A.A().foo())
    }
}
