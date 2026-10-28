interface ReifiedNullableMarker
open class ReifiedNullableA : ReifiedNullableMarker
class ReifiedNullableChild : ReifiedNullableA()
class ReifiedNullableOther

inline fun <reified T> Any?.isNullableT(): Boolean = this is T?
inline fun <reified T> Any?.isNotNullableT(): Boolean = this !is T?
inline fun <reified T> Any?.castNullableT(): T? = this as T?
inline fun <reified T> Any?.safeCastNullableT(): T? = this as? T?
inline fun <reified T> Any?.isT(): Boolean = this is T
inline fun <reified T> Any?.forwardNullableT(): Boolean = this.isT<T?>()
inline fun <reified T> nullablePredicate(): (Any?) -> Boolean = { it is T? }

fun main() {
    println("checks")
    println(null.isNullableT<ReifiedNullableA>())
    println(ReifiedNullableA().isNullableT<ReifiedNullableA>())
    println(ReifiedNullableChild().isNullableT<ReifiedNullableA>())
    println(ReifiedNullableA().isNullableT<ReifiedNullableMarker>())
    println(ReifiedNullableOther().isNullableT<ReifiedNullableA>())
    println(ReifiedNullableA().isNotNullableT<ReifiedNullableA>())
    println(ReifiedNullableOther().isNotNullableT<ReifiedNullableA>())
    println(null.isNullableT<ReifiedNullableA?>())
    println(ReifiedNullableA().isNullableT<ReifiedNullableA?>())
    println(42.isNullableT<Int>())
    println(42.isNullableT<String>())
    println(null.isT<ReifiedNullableA>())
    println(null.isT<ReifiedNullableA?>())

    println("forwarded")
    println(null.forwardNullableT<ReifiedNullableA>())
    println(ReifiedNullableA().forwardNullableT<ReifiedNullableA>())
    println(ReifiedNullableOther().forwardNullableT<ReifiedNullableA>())
    println(ReifiedNullableA().forwardNullableT<ReifiedNullableA?>())

    println("captured")
    val predicate = nullablePredicate<ReifiedNullableA>()
    println(predicate(null))
    println(predicate(ReifiedNullableA()))
    println(predicate(ReifiedNullableOther()))

    println("casts")
    println(null.castNullableT<ReifiedNullableA>() == null)
    println(ReifiedNullableA().castNullableT<ReifiedNullableA>() != null)
    println(ReifiedNullableA().safeCastNullableT<ReifiedNullableA>() != null)
    println(ReifiedNullableOther().safeCastNullableT<ReifiedNullableA>() == null)
    try {
        ReifiedNullableOther().castNullableT<ReifiedNullableA>()
        println("unexpected")
    } catch (error: ClassCastException) {
        println("caught")
    }
}
