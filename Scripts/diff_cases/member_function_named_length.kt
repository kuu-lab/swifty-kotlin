class NameBox(val name: String?) {
    fun length() = name?.let { it.length }
}

fun main() {
    println(NameBox("x").length())
    println(NameBox(null).length())
}
