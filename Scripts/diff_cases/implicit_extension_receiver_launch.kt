interface CC
class Context : CC
interface Job { val value: Int }
class Result(override val value: Int) : Job
interface CScope { val value: Int }
class Scope(override val value: Int) : CScope

fun CScope.launch(context: CC, block: suspend CScope.() -> Unit): Job = Result(value)
fun CScope.reader(context: CC): Int {
    val implicit = launch(context) { }
    val explicit = this.launch(context) { }
    return implicit.value + explicit.value
}

interface Source
class Input : Source
fun Source.readCodePointValue(): Int = 42
fun Source.readUtf8ExactCharacters(): Int = readCodePointValue()

fun main() {
    println(Scope(21).reader(Context()))
    println(Input().readUtf8ExactCharacters())
}
