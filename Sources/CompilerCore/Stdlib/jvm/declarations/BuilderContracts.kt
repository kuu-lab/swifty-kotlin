package kotlin.contracts
// Contract effects are compiler-only and are erased before JVM emission.
interface ContractEffect
interface Effect : ContractEffect
interface ConditionalEffect : Effect
interface SimpleEffect : Effect {
    infix fun implies(booleanExpression: Boolean): ConditionalEffect
}
interface Returns : SimpleEffect
interface ReturnsNotNull : SimpleEffect
interface CallsInPlace: Effect
interface ContractBuilder {
    fun returns(): Returns
    fun returns(value: Any?): Returns
    fun returnsNotNull(): ReturnsNotNull
    fun <R> callsInPlace(lambda: Function<R>, kind: InvocationKind = InvocationKind.UNKNOWN): CallsInPlace
}
enum class InvocationKind { AT_MOST_ONCE, AT_LEAST_ONCE, EXACTLY_ONCE, UNKNOWN }
inline fun contract(builder: ContractBuilder.() -> Unit) {}
