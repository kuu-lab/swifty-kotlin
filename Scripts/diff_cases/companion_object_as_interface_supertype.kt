interface Factory<T> { fun create(): T }
class Widget(val id: Int) {
    override fun toString() = "W$id"
    companion object : Factory<Widget> {
        var next = 0
        override fun create() = Widget(next++)
    }
}
object Plain : Factory<String> { override fun create() = "p" }
fun <T> makeTwo(f: Factory<T>): List<T> = listOf(f.create(), f.create())

fun main() {
    println(makeTwo(Plain))
    println(makeTwo(Widget))
    val f: Factory<Widget> = Widget
    println(f.create())
    val g: Factory<Widget> = Widget.Companion
    println(g.create())
}
