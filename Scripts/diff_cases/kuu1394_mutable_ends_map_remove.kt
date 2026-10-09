// KUU-1394: MutableList.addFirst/addLast and MutableMap.remove(key, value)
// were missing from the bundled stdlib surface (on JVM they resolve as
// java.util.SequencedCollection members of List and the java.util.Map.remove
// key/value default method). ArrayDeque's own addFirst/addLast members must
// keep winning over the new extensions, and the two-argument remove must
// only drop the entry when the key is currently mapped to the given value.
fun main() {
    val l = mutableListOf(2, 3)
    l.addFirst(1)
    l.addLast(4)
    println(l)
    println(l.removeFirst())
    println(l.removeLast())

    val e = mutableListOf<Int>()
    e.addLast(5)
    e.addFirst(0)
    println(e)

    val d = ArrayDeque<Int>()
    d.addFirst(1)
    d.addLast(2)
    println(d)

    val m = mutableMapOf(1 to "a", 2 to "b")
    println(m.remove(1, "a"))
    println(m.remove(1, "a"))
    println(m.remove(2, "x"))
    println(m.remove(9, "a"))

    val n = mutableMapOf<String, Int?>("a" to null, "b" to 2)
    println(n.remove("a", null))
    println(n.remove("b", null))
    println(n.remove("z", null))

    val p: MutableMap<out Int, String> = mutableMapOf(5 to "v")
    println(p.remove(5, "v"))

    println(m)
    println(l)
}
