// KUU-3769: a member typealias can reference a nested type declared in the
// same class body by its unqualified name — the kotlinx-cli ArgParser.kt:215
// pattern (`typealias OPTION_PREFIX_STYLE = OptionPrefixStyle` where
// `enum class OptionPrefixStyle` is a sibling member). Previously failed
// with SEMA-0025 Unresolved type; also covers declaration-order
// independence and a nested-class (non-enum) target.

class ArgParser {
    enum class OptionPrefixStyle { LONG, SHORT, JVM }
    typealias OPTION_PREFIX_STYLE = OptionPrefixStyle

    private val style: OPTION_PREFIX_STYLE = OPTION_PREFIX_STYLE.JVM

    fun current(): OPTION_PREFIX_STYLE = style
    fun isLong(): Boolean = style == OPTION_PREFIX_STYLE.LONG
}

class Holder {
    // Sibling declared after the alias must still resolve.
    typealias T = E
    enum class E { X, Y }
    fun f(): T = T.X
}

class Box {
    class N(val v: Int)
    typealias Alias = N
    fun make(): Alias = Alias(7)
}

fun main() {
    val parser = ArgParser()
    println(parser.current())
    println(parser.isLong())
    println(Holder().f())
    println(Box().make().v)
}
