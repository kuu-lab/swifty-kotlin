fun box(): String {
    val x = object {
        fun <S> foo(value: S): S = value
    }
    return x.foo("OK")
}

fun main() {
    println(box())
}
