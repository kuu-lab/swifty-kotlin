// KUU-2361: a lambda result must infer T through a generic fun-interface parameter.
fun interface IFoo<T> { fun foo(): T }

var state = ""

fun <T> consume(foo: IFoo<T>) {
    foo.foo()
}

fun box(): String {
    consume { state = "OK" }
    return state
}

fun main() {
    println(box())
}
