// KUU-2466: `by lazy(initializer)` on a generic member must preserve its Function0 argument.
class Holder<T>(val initializer: () -> T) {
    val value: T by lazy(initializer)
}

fun main() {
    print(Holder<String> { "K" }.value)
}
