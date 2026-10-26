// KUU-3352: a vararg callable reference adapts to a function type with a type-variable input.
fun <T> foo(b: (Any, T) -> String): String = b("O", "K" as T)
fun of(vararg args: Any): String = args[0].toString() + args[1].toString()
fun main() { println(foo(::of)) }
