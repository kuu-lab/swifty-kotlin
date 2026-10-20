class Text(val n: Int) {
    override fun toString(): String { println("str$n"); return "T$n" }
}
fun make(n: Int): Text { println("arg$n"); return Text(n) }
fun effect() { println("effect") }
@JvmInline value class U(val value: UInt)
fun <T> render(value: T): String = "<$value>"
fun main() {
    val name = "界"; val n = 42
    println("hello $name: ${n + 1}")
    println("" + make(1) + make(2))
    println("${make(3)}:${make(4)}")
    println("unit=${effect()}")
    val missing: String? = null; println(missing + "x"); println("$missing")
    println("$n/${1.5}/${true}/${'界'}/${255u.toUByte()}/${ULong.MAX_VALUE}")
    println(render(U(4294967295u)))
    println("escape\n\t\"\$name")
    println("${"nested=$n"}")
    val chars = charArrayOf('A', 'B'); val ints = intArrayOf(1, 2)
    println("$chars".startsWith("[C@")); println(("" + ints).startsWith("[I@"))
    println('A' + "BC")
    var x = 1; val text = "${x++}/${x++}/$x"; println(text)
}
