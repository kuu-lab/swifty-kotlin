// Based on Kotlin compiler testData/codegen/box/enum/companionObjectInEnum.kt
// at 679366a83f99851b42f64795f10ed803ff011c73.
enum class Game {
    ROCK,
    PAPER,
    SCISSORS;

    fun memberValues() = values()

    companion object {
        fun foo() = ROCK
        val bar = PAPER
        val values2 = values()
        val scissors = valueOf("SCISSORS")
    }
}

fun box(): String {
    if (Game.foo() != Game.ROCK) return "Fail 1"
    if (Game.bar != Game.PAPER) return "Fail 2: ${Game.bar}"
    if (Game.values().size != 3) return "Fail 3"
    if (Game.valueOf("SCISSORS") != Game.SCISSORS) return "Fail 4"
    if (Game.values2.size != 3) return "Fail 5"
    if (Game.scissors != Game.SCISSORS) return "Fail 6"
    if (Game.ROCK.memberValues().size != 3) return "Fail 7"
    if (enumValues<Game>().size != 3) return "Fail 8"
    return "OK"
}

fun main() {
    println(box())
}
