interface Getter<T> { fun get(): T }
fun <T> getter(value: T): Getter<T> = object: Getter<T> { override fun get(): T = value }
class Outer<T>(val value: T) { inner class Inner<U>(val other: U) { fun first(): T = value; fun second(): U = other } }
fun main() { val x = Outer(42).Inner("inner"); println(x.first()); println(x.second()); println(getter("anonymous").get()) }
