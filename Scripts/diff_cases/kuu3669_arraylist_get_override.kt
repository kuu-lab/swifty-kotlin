open class BaseStringList : ArrayList<String>()

class StringList : BaseStringList() {
    public override fun get(index: Int): String = "StringList.get()"
}

fun main() {
    val l: BaseStringList = StringList()
    println(l.get(0))
    println(l[0])
}
