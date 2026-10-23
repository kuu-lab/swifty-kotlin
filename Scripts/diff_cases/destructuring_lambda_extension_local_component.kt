class A<T>(val x: String, val y: String, val z: T)

operator fun A<*>.component1() = x

fun <T, R> foo(value: T, block: (T) -> R): R = block(value)

object B {
    operator fun A<*>.component2() = y

    fun bar(): String {
        operator fun <R> A<R>.component3() = z
        return foo(A("O", "K", 123)) { (x, y, z) -> x + y + z.toString() }
    }

    fun barWithCapturedLocal(): String {
        val suffix = "!"
        operator fun <R> A<R>.component3() = z.toString() + suffix
        return foo(A("O", "K", 123)) { (x, y, z) -> x + y + z.toString() }
    }
}

fun main() {
    println(B.bar())
    println(B.barWithCapturedLocal())
}
