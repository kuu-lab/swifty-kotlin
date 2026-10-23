class A {
    fun test(): Boolean {
        val foo: String.() -> Boolean = { false }
        fun String.foo(): Boolean = true
        return with("2") { foo() }
    }
}

fun receiverMismatchKeepsExtension(): Boolean {
    val foo: Int.() -> Boolean = { false }
    fun String.foo(): Boolean = true
    return with("2") { foo() }
}

fun main() {
    println(A().test())
    println(receiverMismatchKeepsExtension())
}
