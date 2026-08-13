class Tags : LinkedHashSet<String>()

class NamedSet(val name: String) : LinkedHashSet<String>()

fun main() {
    val t = Tags()
    t.add("kotlin")
    println(t.size)
    println(t.contains("kotlin"))

    val n = NamedSet("myset")
    n.add("java")
    println(n.size)
    println(n.name)
    println(n.contains("java"))

    val base = LinkedHashSet<String>()
    base.add("a")
    println(base.size)
}
