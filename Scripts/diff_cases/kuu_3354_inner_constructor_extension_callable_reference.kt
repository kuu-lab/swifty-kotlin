class Foo<T> {
    inner class Bar<T> {
        val result: String = "OK"
    }
}

fun <T> foo(factory: Foo<T>.() -> Foo<T>.Bar<T>) {
    println(factory(Foo()).result)
}

fun main() {
    foo(Foo<Int>::Bar)
}
