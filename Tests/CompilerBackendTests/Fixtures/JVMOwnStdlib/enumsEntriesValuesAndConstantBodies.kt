enum class Mode(val code: Int) {
    FIRST(20) { override fun result(): Int = code * 2 },
    SECOND(22) { override fun result(): Int = code + 20 };
    abstract fun result(): Int
    companion object { fun total(): Int = FIRST.code + SECOND.code }
}
enum class Flag { ON { override val value: Int = 42 }; abstract val value: Int }
enum class Empty { ; abstract fun unused(): Int }
fun main() {
    println(Mode.FIRST.name)
    println(Mode.SECOND.ordinal)
    println(Mode.FIRST.result())
    println(Mode.valueOf("SECOND").result())
    println(Mode.total())
    val values = Mode.values()
    values[0] = Mode.SECOND
    println(Mode.values()[0].name)
    println(Mode.entries.size)
    println(Mode.entries[1].name)
    for (mode in Mode.entries) { println(mode.code) }
    try { Mode.valueOf("missing") } catch (error: IllegalArgumentException) { println("missing") }
    println(Flag.ON.value)
    println(Empty.values().size)
}
