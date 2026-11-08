// KUU-4495: a nullable implicit receiver must not satisfy a non-null
// extension receiver; Kotlin falls through to the outer receiver instead.
interface Reader4495 { fun read(): Int }

fun String.firstCode4495(): Int = get(0).code

fun String.viaObjectLiteral4495(): Reader4495 = with(null as String?) {
    object : Reader4495 {
        override fun read(): Int = firstCode4495()
    }
}

fun String.viaNullableScope4495(): Int = with(null as String?) { firstCode4495() }
fun String.viaNonNullScope4495(): Int = with("ab") { firstCode4495() }

fun main() {
    println("L".viaObjectLiteral4495().read())
    println("L".viaNullableScope4495())
    println("L".viaNonNullScope4495())
}
