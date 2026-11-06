// STDLIB-JVM-165: JVM-specific annotations and wrappers.
// Verifies that member-level JVM annotations are accepted and
// that default-argument Java overload entrypoints can be synthesized.

@OptIn(ExperimentalStdlibApi::class)
@JvmExposeBoxed
@JvmInline
value class Score(val value: Int)

@OptIn(ExperimentalStdlibApi::class)
@JvmExposeBoxed(jvmName = "makeScore")
fun wrapScore(raw: Int): Score = Score(raw)

class Greeter {
    companion object {
        @JvmField
        var counter: Int = 0

        @JvmStatic
        fun bump() {
            counter++
        }
    }

    @JvmName("helloForJava")
    @JvmOverloads
    fun greet(prefix: String = "Hello", suffix: String = "!"): String {
        return prefix + suffix
    }
}

fun main() {
    Greeter.bump()
    println("counter=${Greeter.counter}")

    val greeter = Greeter()
    println(greeter.greet())
    println(greeter.greet("Hi"))
    println(greeter.greet("Welcome", "!!!"))

    println(Score(9).value)
    println(wrapScore(4).value)
}
