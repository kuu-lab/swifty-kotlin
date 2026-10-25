class Grid(val w: Int) {
    fun runRecv(): Int = "abc".run { length + w }
    fun runNested(): Int = "ab".run { length + "cd".run { length + w } }
    fun runMember(): String = 5.run { (this + w).toString() }
    fun runCatchingCap(): Int = "q".runCatching { length + w }.getOrThrow()
    fun letCap(): Int = "xy".let { it.length + w }
}

fun main() {
    val g = Grid(3)
    println(g.runRecv())
    println(g.runNested())
    println(g.runMember())
    println(g.runCatchingCap())
    println(g.letCap())
    val s: String? = "hey"
    println(s?.let { it.length })
}
