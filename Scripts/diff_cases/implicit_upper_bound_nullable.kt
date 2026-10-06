fun <X> makeIt(x: X): X = x
fun f() = makeIt<Int?>(null)
fun inferred() = makeIt(null)
fun <X : Any?> nullableBound(x: X): X = x

class P<T : Any> {
    fun g() = makeIt<T?>(null)
}

class Box<T>(val value: T) {
    fun <U> echo(value: U): U = value
}

fun main() {
    println(f())
    println(P<Int>().g())
    println(makeIt<Int?>(null))
    println(makeIt<Int?>(42))
    println(makeIt<String?>("hello"))
    println(makeIt<String?>(null))
    println(makeIt<Any?>(null))
    println(inferred())
    println(nullableBound<Int?>(null))
    val box = Box<Int?>(null)
    println(box.value)
    println(box.echo<String?>(null))
    println(box.echo<String?>("member"))
}
