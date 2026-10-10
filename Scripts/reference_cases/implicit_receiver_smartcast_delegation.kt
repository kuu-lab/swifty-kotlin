interface Basic { val original: String }
interface Names { val names: String }
class Both : Basic, Names {
    override val original = "original"
    override val names = "names"
}
class Plain : Basic { override val original = "plain" }
class Delegated : Basic by
    Both() {
    val extra = 7
}
fun Basic.positive(): String { if (this is Names) return names + original; return original }
fun Basic.negative(): String { if (this !is Names) return original; return names }
val Basic.property: String
    get() { if (this is Names) return names; return original }
class Outer(val value: Int) {
    fun read(): String {
        val obj = object {
            val value = "inner"
            val copied: String = value
        }
        return obj.copied
    }
}
fun main() {
    val both: Basic = Both()
    println(both.positive())
    println(both.negative())
    println(Plain().positive())
    val delegated = Delegated()
    println(delegated.original)
    println(delegated.extra)
    println(Outer(99).read())
    println(both.property)
    println(Plain().property)
}
