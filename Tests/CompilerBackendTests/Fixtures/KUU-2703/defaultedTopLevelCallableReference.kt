fun f(a: Int = 7): Int = a
fun sameArity(a: Int): Int = a
inline fun <reified T> reifiedDefault(value: T, suffix: Int = 2): T = value

fun main() {
    val r: () -> Int = ::f
    println(r())

    val partial: (Int) -> Int = ::f
    println(partial(11))

    val explicitLambda: () -> Int = { f() }
    println(explicitLambda())

    val sameArityReference: (Int) -> Int = ::sameArity
    println(sameArityReference(13))

    val reifiedDefaultReference: (String) -> String = ::reifiedDefault
    println(reifiedDefaultReference("reified"))
}
