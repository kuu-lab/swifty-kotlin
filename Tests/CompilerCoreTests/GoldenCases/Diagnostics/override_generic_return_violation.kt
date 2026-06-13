// DEBT-SEMA-002: generic return-type covariance on override — invalid cases that
// require class type-argument substitution to diagnose correctly.

open class ListProvider<T> {
    open fun items(): List<T> = emptyList()
}

// Base<String> requires List<String>; widening element type to Any is invalid.
class WidenedListProvider : ListProvider<String>() {
    override fun items(): List<Any> = emptyList()
}

open class ValueHolder<T> {
    open fun value(): T = throw RuntimeException()
}

// Base<String> requires String; Any is not a subtype of String.
class WidenedValueHolder : ValueHolder<String>() {
    override fun value(): Any = "x"
}

open class PairHolder<T> {
    open fun pair(): Pair<T, T> = throw RuntimeException()
}

// Base<Int> requires Pair<Int, Int>; second type argument is wrong.
class MismatchedPairHolder : PairHolder<Int>() {
    override fun pair(): Pair<Int, String> = throw RuntimeException()
}

open class Middle<T> : ListProvider<T>()

// Transitive instantiation: Middle<String> -> ListProvider<String>.
class TransitiveWidenedList : Middle<String>() {
    override fun items(): List<Any> = emptyList()
}

open class MethodGenericFactory {
    open fun <R : Number> create(): List<R> = emptyList()
}

// Method type parameter R is not fixed to Int.
class BadMethodGenericFactory : MethodGenericFactory() {
    override fun <R : Number> create(): List<Int> = emptyList()
}
