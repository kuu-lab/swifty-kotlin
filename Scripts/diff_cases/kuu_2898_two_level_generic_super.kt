open class A<R> {
    open fun foo(r: R): R = r
}

open class B : A<String>()

open class C : B() {
    override fun foo(r: String): String = super.foo(r) + "K"
}

fun main() {
    println(C().foo("O"))
}
