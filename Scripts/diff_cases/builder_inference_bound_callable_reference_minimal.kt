import kotlin.experimental.ExperimentalTypeInference

interface Scope<T> { fun emit(value: T) }
abstract class Result<T>

@OptIn(ExperimentalTypeInference::class)
fun <T> build(@BuilderInference block: Scope<T>.() -> Unit): Result<T> = null!!

fun consumeString(action: (String) -> Unit) {}

fun fromNonGenericCallback() = build { consumeString(this::emit) }
fun fromLambdaCallback() = build { consumeString { emit(it) } }

fun box(): String = "OK"
fun main() { print(box()) }
