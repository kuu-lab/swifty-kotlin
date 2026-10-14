// KUU-2110: object property initializers must read the enclosing extension receiver.
interface B { val bar: String }

fun String.foo() = object : B {
    override val bar = length.toString()
}

fun main() {
    println("Hello".foo().bar)
}
