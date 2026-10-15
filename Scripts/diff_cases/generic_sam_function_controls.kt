// KUU-2361: keep existing generic function-type and concrete SAM paths working.
fun interface IFoo<T> { fun foo(): T }

var state = ""

fun <T> consume(foo: IFoo<T>) {
    foo.foo()
}

fun consumeUnit(foo: IFoo<Unit>) {
    foo.foo()
}

fun <T> consumeFunction(block: () -> T) {
    block()
}

fun box(): String {
    state = ""
    consumeUnit { state += "C" }

    val typed: IFoo<Unit> = IFoo { state += "T" }
    consume(typed)

    consume(IFoo<Unit> { state += "E" })
    consumeFunction { state += "F" }
    return state
}

fun main() {
    println(box())
}
