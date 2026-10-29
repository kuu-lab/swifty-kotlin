open class BaseStringList : ArrayList<String>()

class StringList : BaseStringList() {
    public override fun get(index: Int): String = "StringList.get()"
}

fun box(): String {
    val myStringList = StringList()
    myStringList.add("first element")
    if (myStringList.get(0) != "StringList.get()") return "Fail #1"
    val base: BaseStringList = myStringList
    val arrayList: ArrayList<String> = myStringList
    if (base.get(0) != "StringList.get()") return "Fail #2"
    if (arrayList.get(0) != "StringList.get()") return "Fail #3"
    return "OK"
}

fun main() {
    println(box())
}
