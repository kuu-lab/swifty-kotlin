// KUU-2288: JetBrains/kotlin compiler/testData/codegen/box/inference/kt39824.kt
// pinned at 679366a83f99851b42f64795f10ed803ff011c73 (SHA-256 301d279984b9e60ef4838825e3cacb92479c0f41f7235c7bcdc16ae8e26bcc33).
// The diff harness keeps the companion invoke overloads and adapts box() to
// avoid unrelated generic-helper inference and delegated-property runtime gaps.
fun <C : Any> diContext(context: C): DIContext<C> = DIContext(TypeToken(), context)

fun <C : Any> diContext(getContext: () -> C): DIContext<C> = DIContext<C>(TypeToken()) { getContext() }

interface DIContext<C : Any> {
    val type: TypeToken<C>
    val value: C

    fun print() {
        result += value.toString()
    }

    data class Value<C : Any>(override val type: TypeToken<C>, override val value: C) : DIContext<C>

    class Lazy<C : Any>(override val type: TypeToken<C>, public val getValue: () -> C) : DIContext<C> {
        override val value: C get() = getValue()
    }

    companion object {
        operator fun <C : Any> invoke(type: TypeToken<C>, value: C): DIContext<C> = Value(type, value)
        operator fun <C : Any> invoke(type: TypeToken<C>, getValue: () -> C): DIContext<C> = Lazy(type, getValue)
    }
}

class TypeToken<T>

var result = ""

fun box(): String {
    diContext("O").print()
    diContext<String> { "K" }.print()
    return result
}

fun main() {
    print(box())
}
