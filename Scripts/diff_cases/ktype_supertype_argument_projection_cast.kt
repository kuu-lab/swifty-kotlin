// KClass.supertypes argument projections must carry the KTypeProjection
// runtime type so erased-generic claim checkcasts accept them.
import kotlin.reflect.KTypeProjection

open class Base<A, B>
class Child<X> : Base<X, String>()

fun main() {
    val arguments: List<KTypeProjection> = Child::class.supertypes.first().arguments
    println(arguments.size)
    val first: KTypeProjection = arguments.first()
    val last: KTypeProjection = arguments.last()
    println(first.variance)
    println(last.variance)
    println(arguments.map { it.variance })
}
