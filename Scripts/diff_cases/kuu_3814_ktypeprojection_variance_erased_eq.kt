// KUU-3814: a KVariance enum value produced by KTypeProjection.variance must
// carry the same canonical enum box the source-backed enum uses, so erased
// (generic) `==`/`===`, hashCode, and toString behave identically to a direct
// KVariance entry reference. The runtime getter used to hand back a bare
// ordinal Int, which reached erased slots unboxed and compared unequal to the
// entry's tagged singleton box.
import kotlin.reflect.KVariance

fun arrayOut(): Array<out Number> = null!!
fun arrayIn(): Array<in Number> = null!!
fun arrayInvariant(): Array<Number> = null!!
fun arrayStar(): Array<*> = null!!

fun <T> eq(e: T, a: T): Boolean = e == a
fun <T> ident(e: T, a: T): Boolean = e === a
fun assertEq(expected: Any?, actual: Any?) {
    println(expected == actual)
}
fun <T> List<T>.has(x: T): Boolean = contains(x)

fun main() {
    val v = ::arrayOut.returnType.arguments.single().variance
    println(v == KVariance.OUT)          // true
    println(eq(KVariance.OUT, v))        // true
    println(v === KVariance.OUT)         // true
    println(ident(KVariance.OUT, v))     // true
    println(v.toString())                // OUT
    println(v?.name)                     // OUT
    println(v?.ordinal)                  // 2
    println(v?.hashCode() == KVariance.OUT.hashCode()) // true
    assertEq(KVariance.OUT, v)           // true
    println(listOf(KVariance.OUT, KVariance.IN).has(v)) // true

    val inV = ::arrayIn.returnType.arguments.single().variance
    println(eq(KVariance.IN, inV))       // true
    println(eq(KVariance.OUT, inV))      // false
    println(inV.toString())              // IN

    val invV = ::arrayInvariant.returnType.arguments.single().variance
    println(eq(KVariance.INVARIANT, invV)) // true
    println(invV.toString())             // INVARIANT

    // Star projection keeps a null variance.
    val starV = ::arrayStar.returnType.arguments.single().variance
    println(starV == null)               // true
    println(eq<Any?>(null, starV))       // true
    println(starV == KVariance.OUT)      // false

    // KTypeProjection equality/toString exercise the same variance slot.
    println(::arrayOut.returnType.arguments.single())           // out kotlin.Number
    println(::arrayOut.returnType.arguments.single() ==
            ::arrayOut.returnType.arguments.single())           // true
    println(kotlin.reflect.KTypeProjection.covariant(
        ::arrayOut.returnType.arguments.single().type!!).variance == KVariance.OUT) // true
}
