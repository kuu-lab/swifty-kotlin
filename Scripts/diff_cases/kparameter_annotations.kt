// KUU-4017: KParameter.annotations (KAnnotatedElement) on runtime KParameter
// boxes must return an empty list instead of crashing through the interface
// cast, while source-backed KParameter implementations keep their own
// `annotations` through interface dispatch.
import kotlin.reflect.KAnnotatedElement
import kotlin.reflect.KParameter
import kotlin.reflect.KType

class UserParam(override val index: Int, override val name: String) : KParameter {
    override val type: KType get() = throw UnsupportedOperationException()
    override val kind: KParameter.Kind get() = KParameter.Kind.VALUE
    override val isOptional: Boolean get() = false
    override val isVararg: Boolean get() = false
    override val annotations: List<Annotation> get() = listOf(object : Annotation {})
}

class C(val a: Int, val b: String)

fun f(x: Int, y: String = "d") = Unit

fun describe(element: KAnnotatedElement): Int = element.annotations.size

fun main() {
    for (p in ::f.parameters) {
        println("${p.index}:${p.name}:${p.annotations.size}")
    }
    for (p in C::class.constructors.first().parameters) {
        println("${p.index}:${p.name}:${p.annotations.size}")
    }
    val p: KParameter? = ::f.parameters.first()
    println(p?.annotations?.size)
    val u: KParameter = UserParam(0, "u")
    println(u.annotations.size)
    println(describe(::f.parameters.first()))
    println(describe(u))
}
