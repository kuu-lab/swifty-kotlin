fun String.tag(): String = "ext:" + this

class Writer(val value: Int) {
    fun read(): Int = value
}

fun main() {
    val outer = with("s") { with(1) { ::tag } }
    println(outer())
    val deeper = with("deep") { with(1) { with(true) { ::tag } } }
    println(deeper())
    val delayed = with("later") { with(1) { { ::tag } } }
    println(delayed()())
    val nearest = with("outer") { with("inner") { ::tag } }
    println(nearest())
    val member = with(Writer(42)) { with("s") { ::read } }
    println(member())
}
