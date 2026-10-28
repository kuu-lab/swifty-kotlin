import kotlin.experimental.ExperimentalTypeInference

interface Scope<T> {
    fun emit(value: T)
}

class ScopeImpl<T> : Scope<T> {
    override fun emit(value: T) {
        print(value)
    }
}

@OptIn(ExperimentalTypeInference::class)
fun <T> build(@BuilderInference block: Scope<T>.() -> Unit) {
    ScopeImpl<T>().block()
}

fun consumeString(action: (String) -> Unit) {
    action("OK")
}

fun fromBoundReference() {
    build { consumeString(this::emit) }
}

fun fromLambda() {
    build { consumeString { emit(it) } }
}

fun main() {
    fromBoundReference()
}
