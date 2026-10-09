fun String.tag(): String = "ext:$this"

fun main() {
    val ref = with("s") { ::tag }
    println(ref.name)
    println(ref.call())
}
