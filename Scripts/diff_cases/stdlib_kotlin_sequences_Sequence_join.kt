import kotlin.text.Appendable

class ThrowingSequence : Sequence<Int> {
    override fun iterator(): Iterator<Int> = object : Iterator<Int> {
        private var state = 0

        override fun hasNext(): Boolean = state < 2

        override fun next(): Int {
            if (state == 1) throw IllegalStateException("next failed")
            state += 1
            return 7
        }
    }
}

fun main() {
    val values: Sequence<Int> = sequenceOf(1, 2, 3)
    val separator: CharSequence = StringBuilder("|")
    val buffer: Appendable = StringBuilder("seed:")

    println(values.joinTo(
        buffer = buffer,
        separator = separator,
        prefix = "[",
        postfix = "]",
        limit = 2,
        truncated = "!"
    ).toString())
    println(values.joinTo(
        buffer = StringBuilder(),
        separator = separator,
        prefix = "{",
        postfix = "}",
        limit = 2,
        truncated = "!"
    ) { "b$it" }.toString())
    println(values.joinToString(
        separator = separator,
        prefix = "[",
        postfix = "]",
        limit = 2,
        truncated = "!"
    ))
    println(values.joinToString(
        separator = separator,
        prefix = "<",
        postfix = ">",
        limit = 2,
        truncated = "!"
    ) { "v$it" })
    println(values.joinToString(separator = separator, transform = { "n$it" }))
    println(values.joinToString { it.toString() })

    // joinTo returns the same buffer instance it was given.
    val identity = StringBuilder("x")
    println(values.joinTo(identity) === identity)
    println(identity.toString())

    // Defaults: separator ", ", no prefix/postfix, no limit.
    println(sequenceOf(4, 5, 6).joinToString())
    println(emptySequence<Int>().joinToString(prefix = "<", postfix = ">"))

    // limit short-circuits lazily on an infinite sequence.
    println(generateSequence(1) { it + 1 }.joinToString(limit = 3, truncated = "~"))
    println(generateSequence(1) { it + 1 }.joinToString(limit = 0, truncated = "~"))

    // Exceptions thrown by the sequence propagate.
    try {
        ThrowingSequence().joinToString()
        println("no-throw")
    } catch (error: IllegalStateException) {
        println(error.message)
    }
}
