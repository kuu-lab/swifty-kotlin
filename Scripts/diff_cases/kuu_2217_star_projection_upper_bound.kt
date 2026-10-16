// KUU-2217: preserve star-projected declaration bounds while lifting supertypes.
interface A<out T : Any> {
    fun foo(): String
}

interface B<out S : Any, out T : Any> : A<T> {
    val x: S
}

class C<out S : Any, out T : Any>(override val x: S) : B<S, T> {
    override fun foo(): String = "OK"
}

class D(val c: C<*, *>) : B<Any, Any> by c

interface Base<out T> {
    val value: T
}

interface Marker

class Narrow<out T : Marker>(override val value: T) : Base<T>

class MarkerImpl : Marker

fun box(): String {
    val concrete = C<Int, String>(1)
    val broad: C<*, *> = concrete
    val assigned: B<Any, Any> = broad
    val delegated = D(concrete)

    val narrow: Narrow<*> = Narrow<MarkerImpl>(MarkerImpl())
    val narrowBase: Base<Marker> = narrow

    if (assigned.foo() != "OK" || delegated.foo() != "OK") return "FAIL"
    if (narrowBase.value !is MarkerImpl) return "FAIL"
    return "OK"
}

fun main() {
    print(box())
}
