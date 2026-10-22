// DIFF_JVM
// KUU-1970: nullable enum properties and methods after safe calls and smart casts.
enum class Mode(val tag: Int) {
    FAST(1), SLOW(2);
    fun label(suffix: String = "!") = "L$tag$suffix"
    fun num() = tag
}
enum class Action {
    FIRST { override fun label() = "first" },
    SECOND { override fun label() = "second" };
    abstract fun label(): String
}
class Plain { fun label() = "plain" }
object Single { fun label() = "single" }
fun getM(index: Int): Mode? = when (index) {
    0 -> Mode.FAST
    1 -> Mode.SLOW
    else -> null
}
fun getAction(): Action? = Action.SECOND
fun Mode?.asAny(): Any? = this
fun Any?.echo(): Any? = this
fun suffix(): String { println("argument"); return "?" }
fun show(m: Mode?) {
    println("${m?.name} ${m?.ordinal} ${m?.tag}")
    println(m?.label())
    println(m?.num())
    println(m?.asAny())
    println(m?.echo())
    if (m != null) {
        println("${m.name} ${m.ordinal} ${m.tag} ${m.label()}")
        println(m.asAny())
    }
}
fun main() {
    show(getM(0))
    show(getM(1))
    show(getM(2))
    println(getM(2)?.label(suffix()))
    val action = getAction()
    println(action?.label())
    if (action != null) println(action.label())
    println(Mode.FAST.label())
    println(Mode.SLOW.name)
    println(Mode.FAST.num())
    val plain: Plain? = Plain()
    println(plain?.label())
    val single: Single? = Single
    println(single?.label())
}
