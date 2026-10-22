package kotlin.contracts
// Contract effects are compiler-only and are erased before JVM emission.
interface Effect
interface CallsInPlace: Effect
interface ContractBuilder {
    fun <R> callsInPlace(lambda: Function<R>, kind: InvocationKind = InvocationKind.UNKNOWN): CallsInPlace
}
enum class InvocationKind { AT_MOST_ONCE, AT_LEAST_ONCE, EXACTLY_ONCE, UNKNOWN }
inline fun contract(builder: ContractBuilder.() -> Unit) {}
