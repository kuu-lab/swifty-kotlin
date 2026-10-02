import kotlin.reflect.KTypeProjection
import kotlin.reflect.KVariance
import kotlin.reflect.typeOf

fun main() {
    val star = KTypeProjection.STAR
    println(star)
    println(star.variance)
    println(star.type)
    println(star === KTypeProjection.STAR)
    println(star == KTypeProjection(null, null))

    val invariant = KTypeProjection.invariant(typeOf<String>())
    println(invariant)
    println(invariant.variance == KVariance.INVARIANT)
    println(invariant.type)

    val contravariant = KTypeProjection.contravariant(typeOf<Int>())
    println(contravariant)
    println(contravariant.variance == KVariance.IN)

    val covariant = KTypeProjection.Companion.covariant(typeOf<List<String>>())
    println(covariant)
    println(covariant.variance == KVariance.OUT)
}
