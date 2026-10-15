interface Base { fun base(): String }
interface Entry { fun entry(): String }
class Delegate : Entry { override fun entry() = "entry" }
class SameLine(private val delegate: Entry) : Base, Entry by delegate {
    override fun base() = "same"
}
class AfterComma(private val delegate: Entry) : Base,
    Entry by delegate {
    override fun base() = "comma"
}
class BeforeBy(private val delegate: Entry) : Base, Entry
    by delegate {
    override fun base() = "newline"
}
fun main() {
    val delegate = Delegate()
    val same = SameLine(delegate)
    val comma = AfterComma(delegate)
    val newline = BeforeBy(delegate)
    println(same.base() + ":" + same.entry())
    println(comma.base() + ":" + comma.entry())
    println(newline.base() + ":" + newline.entry())
}
