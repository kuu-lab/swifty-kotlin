// KUU-2147: preserve fixed slots and alias-to-owner type argument order.
class AliasPayload<A, B>(val first: A, val second: B)
typealias TextPayload<T> = AliasPayload<String, T>
typealias ReversedPayload<X, Y> = AliasPayload<Y, X>
typealias FixedPayload = AliasPayload<String, String>
typealias ChainedPayload<T> = TextPayload<T>

fun main() {
    val explicit = TextPayload<Int>("x", 1)
    val inferred = TextPayload("y", 2)
    val reversed = ReversedPayload<Int, String>("z", 3)
    val fixed = FixedPayload("O", "K")
    val chained = ChainedPayload<Int>("c", 4)
    val widened = TextPayload<Long>("w", 5)
    println(explicit.first)
    println(explicit.second)
    println(inferred.first)
    println(inferred.second)
    println(reversed.first)
    println(reversed.second)
    println(fixed.first + fixed.second)
    println(chained.first)
    println(chained.second)
    println(widened.first)
    println(widened.second)
}
