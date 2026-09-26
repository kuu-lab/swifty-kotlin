import kotlin.reflect.KTypeProjection
import kotlin.reflect.typeOf

fun main() {
    val firstLong = typeOf<Long>()
    val secondLong = typeOf<Long>()
    println(firstLong == secondLong)
    println(firstLong.hashCode() == secondLong.hashCode())
    println(firstLong == typeOf<Long?>())

    val star = typeOf<List<*>>().arguments[0]
    println(star === KTypeProjection.STAR)
    println(star == KTypeProjection(null, null))

    val covariant = KTypeProjection.covariant(typeOf<Long>())
    val projected = typeOf<MutableList<out Long>>().arguments[0]
    println(covariant == projected)
    println(covariant.hashCode() == projected.hashCode())
}
