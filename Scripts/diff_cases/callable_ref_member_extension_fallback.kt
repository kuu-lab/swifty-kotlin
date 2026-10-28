interface Visible

class Box : Visible {
    fun render(): String = "member"
}

fun Box.render(): String = "shadowed"
fun Visible.render(value: Int): String = "broad:$value"
fun Box.render(value: Int): String = "box:$value"

fun main() {
    val box = Box()
    val member: (Box) -> String = Box::render
    val extension: (Box, Int) -> String = Box::render
    val boundMember: () -> String = box::render
    val boundExtension: (Int) -> String = box::render
    println(member(box))
    println(extension(box, 7))
    println(boundMember())
    println(boundExtension(9))
}
