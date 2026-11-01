import java.util.TreeMap
import java.util.TreeSet

class DescendingMap : TreeMap<Int, String>(reverseOrder<Int>())
class DescendingSet : TreeSet<Int>(reverseOrder<Int>())
class LengthSet : TreeSet<String>(compareBy<String> { it.length })
class NaturalMap : TreeMap<Int, String>(null as Comparator<Int>?)

fun main() {
    val map = DescendingMap()
    map[1] = "a"; map[3] = "c"; map[2] = "b"
    println(map.keys.toList())
    println(map.firstKey())
    println(map.comparator() != null)

    val set = DescendingSet()
    set.add(1); set.add(3); set.add(2)
    println(set.toList())
    println(set.first())

    val lengths = LengthSet()
    lengths.add("ccc"); lengths.add("a"); lengths.add("bb"); lengths.add("dd")
    println(lengths.toList())

    val natural = NaturalMap()
    natural[2] = "b"; natural[1] = "a"
    println(natural.keys.toList())
    println(natural.comparator() == null)

    val direct = TreeMap<Int, String>(reverseOrder<Int>())
    direct[1] = "a"; direct[3] = "c"
    println(direct.keys.toList())
}
