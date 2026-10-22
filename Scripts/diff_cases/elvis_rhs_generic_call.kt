// DIFF_JVM
// KUU-2454: an Elvis RHS generic call can use the LHS non-null type to infer
// otherwise-unconstrained result variables, without constraining input-inferred
// type variables that participate in the Elvis LUB.
interface Consumer<in T>

fun <T> buildConsumer(b: Boolean, block: (Consumer<T>) -> Unit): T? =
    if (b) ("O" as T) else null

fun expectConsumerString(value: Consumer<String>) {}

fun <T> maybe(value: T): T? = value
fun <T> materialize(): T = "K" as T

fun original(b: Boolean) =
    buildConsumer(b) { expectConsumerString(it) } ?: materialize()

fun minimal() = maybe("O") ?: materialize()
fun explicitReturnType(): String = maybe("O") ?: materialize()
fun explicitTypeArguments() = maybe("O") ?: materialize<String>()

fun <T> identity(value: T): T = value
fun heterogeneous(value: String?) = value ?: identity(42)

fun box(): String = original(true) + original(false)

fun main() {
    println(box())
    println(minimal())
    println(explicitReturnType())
    println(explicitTypeArguments())
    println(heterogeneous(null))
}
