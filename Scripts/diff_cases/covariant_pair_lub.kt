// KUU-1997: infer the common argument parent before checking probe's return type.
open class Module
class A: Module()
class B: Module()
class Other
class Pair<out F, out S>(val first: F, val second: S)
fun choose(flag: Boolean) = if (flag) Pair("x", A()) else Pair("x", B())
fun probe(flag: Boolean): Pair<String, Module> = choose(flag)

fun reversed(flag: Boolean) = if (flag) Pair("x", B()) else Pair("x", A())
fun nullable(flag: Boolean, a: A?) = if (flag) Pair("x", a) else Pair("x", B())
fun probeNullable(flag: Boolean, a: A?): Pair<String, Module?> = nullable(flag, a)
fun unrelated(flag: Boolean) = if (flag) Pair("x", A()) else Pair("x", Other())
fun probeUnrelated(flag: Boolean): Pair<String, Any> = unrelated(flag)

open class Base<out T>(val value: T)
class Left<T>(value: T): Base<T>(value)
class Right<T>(value: T): Base<T>(value)
fun inherited(flag: Boolean) = if (flag) Left(A()) else Right(B())
fun probeInherited(flag: Boolean): Base<Module> = inherited(flag)

fun main() {
    println(probe(true).first)
    println(probe(true).second is A)
    println(probe(false).second is B)
    val reverse: Pair<String, Module> = reversed(true)
    println(reverse.second is B)
    println(probeNullable(true, null).second == null)
    println(probeNullable(false, null).second is B)
    println(probeUnrelated(false).second is Other)
    println(probeInherited(true).value is A)
    println(probeInherited(false).value is B)
}
