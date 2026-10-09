// KUU-1279: class-name shorthand must search the companion's supertypes.
open class Root {
    open fun who(): String = "base"
    open val tag: String get() = "base-tag"
    fun choose(value: Int): Int = value + 1
}
open class Base : Root()
fun Base.who(): String = "extension"
val Base.tag: String get() = "extension-tag"
class WithComp {
    fun who(): Int = 99
    val tag: Int = 99
    companion object : Base() {
        fun make(): Int = 1
        fun choose(value: String): String = value
    }
}
class Named {
    companion object Factory : Base() {
        override fun who(): String = "named"
        override val tag: String get() = "named-tag"
    }
}
interface Labelled {
    fun label(): String = "interface"
    val labelTag: String get() = "interface-tag"
}
class FromInterface { companion object : Labelled }
class WithObj { object Inst : Base() }

fun main() {
    println(WithComp.Companion.who())
    println(WithComp.who())
    println(WithComp.make())
    println(WithComp.Companion.tag)
    println(WithComp.tag)
    println(WithComp.choose(3))
    println(WithComp.choose("own"))
    println(Named.Factory.who())
    println(Named.who())
    println(Named.tag)
    println(FromInterface.label())
    println(FromInterface.labelTag)
    println(WithObj.Inst.who())
    println(WithObj.Inst.tag)
}
