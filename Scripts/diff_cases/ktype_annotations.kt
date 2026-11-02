// KUU-4068: KType.annotations (KAnnotatedElement) on runtime KType boxes must
// return an empty list instead of failing sema or crashing through the
// interface cast, while source-backed KType implementations keep their own
// `annotations` through interface dispatch.
import kotlin.reflect.KAnnotatedElement
import kotlin.reflect.KClassifier
import kotlin.reflect.KType
import kotlin.reflect.KTypeProjection
import kotlin.reflect.typeOf

class UserType(override val classifier: KClassifier?, override val isMarkedNullable: Boolean) : KType {
    override val arguments: List<KTypeProjection> get() = emptyList()
    override val annotations: List<Annotation> get() = listOf(object : Annotation {}, object : Annotation {})
}

fun f(x: Int) = Unit

fun describe(element: KAnnotatedElement): Int = element.annotations.size

fun main() {
    val t = ::f.parameters.first().type
    println(t.annotations.size)
    println(typeOf<Int>().annotations.size)
    println(typeOf<List<String>>().annotations.size)
    println(::f.returnType.annotations.size)
    val u: KType = UserType(null, false)
    println(u.annotations.size)
    val tn: KType? = ::f.parameters.first().type
    println(tn?.annotations?.size)
    println(describe(t))
    println(describe(u))
}
