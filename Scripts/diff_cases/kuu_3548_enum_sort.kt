// KUU-3548: sorting an enum array crashed inside Array<out T>.sort()'s
// `(this as Array<Any?>)` cast when the array came from values() /
// enumValues<T>() — those runtime intrinsics allocated a RuntimeArrayBox
// without the kotlin.Array nominal tag (or reified component descriptor)
// that arrayOf(...) creation sites emit via kk_array_tag_type and
// __kk_array_tag_component, so the erased object failed `is Array`.

enum class Game { ROCK, PAPER, SCISSORS, LIZARD, SPOCK }

fun main() {
    val a = arrayOf(Game.LIZARD, Game.SCISSORS, Game.SPOCK, Game.ROCK, Game.PAPER)
    a.sort()
    println(a.joinToString(" "))

    val v = Game.values()
    v.sort()
    println(v.joinToString(" "))
    println(v is Array<*>)

    val r = enumValues<Game>()
    r.sort()
    println(r.joinToString(" "))

    val erased: Any = Game.values()
    println((erased as Array<Game>).joinToString(" "))
    try {
        @Suppress("UNCHECKED_CAST")
        erased as Array<String>
        println("bad-cast")
    } catch (e: ClassCastException) {
        println("cast-failed")
    }
}
