// KUU-1975: explicit and aliased reflection casts retain T / T? and the JVM exception type.
import kotlin.reflect.KClass
import kotlin.reflect.full.cast
import kotlin.reflect.full.safeCast
import kotlin.reflect.full.cast as castFromFull
import kotlin.reflect.full.safeCast as safeCastFromFull

class CastBox(val value: Int)

fun <T : Any> castAliased(klass: KClass<T>, value: Any?): T = klass.castFromFull(value)
fun <T : Any> safeCastAliased(klass: KClass<T>, value: Any?): T? = klass.safeCastFromFull(value)

fun main() {
    val text: String = String::class.cast("typed")
    val number: Int = Int::class.castFromFull(7)
    val optionalText: String? = String::class.safeCastFromFull("hello")
    val optionalNumber: Int? = safeCastAliased(Int::class, 8)
    val box: CastBox = castAliased(CastBox::class, CastBox(3))
    println(text.length)
    println(number + 1)
    println(optionalText?.length)
    println(optionalNumber?.plus(1))
    println(box.value)
    println(String::class.safeCast(null))
    println(String::class.safeCastFromFull(1))
    println(CastBox::class.safeCastFromFull("wrong"))
    println(safeCastAliased(Int::class, null))

    try {
        Int::class.cast("wrong")
        println("missing")
    } catch (e: TypeCastException) {
        println("wrong:TypeCastException")
    } catch (e: ClassCastException) {
        println("wrong:ClassCastException")
    }
    try {
        String::class.castFromFull(null)
        println("missing")
    } catch (e: TypeCastException) {
        println("null:TypeCastException")
    } catch (e: ClassCastException) {
        println("null:ClassCastException")
    }
}
