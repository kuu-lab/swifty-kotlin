fun main() {
    val dest: MutableList<Int> = listOf(1, 2).mapTo(mutableListOf()) { it * 2 }
    println(dest)
}
