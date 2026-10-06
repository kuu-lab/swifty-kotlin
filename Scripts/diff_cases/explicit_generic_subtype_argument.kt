abstract class ArgType<T : Any>(val hasParameter: kotlin.Boolean)
open class Impl : ArgType<kotlin.Boolean>(false)
object Bool2 : ArgType<Boolean>(false)
object QualifiedBool : ArgType<kotlin.Boolean>(false)
class Opt1<T : Any>(val type: ArgType<T>)

fun <T : Any> take(t: ArgType<T>) {
    println(t.hasParameter)
}

fun main() {
    val inferred = Opt1(Impl())
    val explicit = Opt1<Boolean>(Impl())
    val singleton = Opt1<Boolean>(Bool2)
    val cast = Opt1<Boolean>(Bool2 as ArgType<Boolean>)
    println(inferred.type.hasParameter)
    println(explicit.type.hasParameter)
    println(singleton.type.hasParameter)
    println(cast.type.hasParameter)
    take<Boolean>(Impl())
    take<Boolean>(Bool2)
    take<Boolean>(QualifiedBool)
}
