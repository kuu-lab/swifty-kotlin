// KUU-4083: a return-type colon on the line after the signature must stay
// inside the function declaration (the clikt `fun R.unique()\n    : R` style).

class Box(val tag: String)

fun Box.shout()
        : Box {
    return Box(tag + "!")
}

fun <T> List<T>.second()
        : T? {
    return if (size > 1) this[1] else null
}

fun Int.twice()
        : Int
        = this * 2

fun main() {
    println(Box("a").shout().tag)
    println(listOf(1, 2, 3).second())
    println(21.twice())
}
