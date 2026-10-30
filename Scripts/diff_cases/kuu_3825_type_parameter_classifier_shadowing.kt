import kotlin.reflect.KTypeParameter
import kotlin.reflect.typeOf

class Container<T>

class C<X, Y> {
    fun createX(): KTypeParameter =
        typeOf<Container<X>>().arguments.single().type!!.classifier as KTypeParameter

    fun <X> createIrrelevantX(): KTypeParameter =
        typeOf<Container<X>>().arguments.single().type!!.classifier as KTypeParameter
}

fun main() {
    val c = C<Any, Any>()
    val xCls = c.createX()
    val xFun = c.createIrrelevantX<Any>()
    // KTypeParameter.toString() renders the parameter name, and parameters
    // declared on different declarations are never equal even with the
    // same name.
    println("xFun=$xFun")
    println("xCls=$xCls")
    println("neq=${xCls != xFun}")
    println("eq=${xCls == c.createX()}")
    println("eq2=${xFun == c.createIrrelevantX<Any>()}")
}
