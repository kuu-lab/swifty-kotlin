// KUU-2067: KotlinPoet's accessor modifier set needs EnumSet.noneOf(Class<E>).
// KOTLINC_FLAGS: -Xjdk-release=17
import java.util.EnumSet
import java.util.EnumSet as ModifierSet

enum class Kind { ONE, TWO, THREE }
enum class Other { ONE }
class Plain

fun empty(type: java.lang.Class<Kind>): MutableSet<Kind> = EnumSet.noneOf(type)

fun main() {
    val type: java.lang.Class<Kind> = Kind.ONE.javaClass
    val set = empty(type)
    println(set.size)
    println(set.isEmpty())
    println(set.add(Kind.THREE))
    println(set.add(Kind.ONE))
    println(set.add(Kind.THREE))
    println(set.addAll(listOf(Kind.TWO, Kind.ONE)))
    println(set.joinToString(","))
    println(set.contains(Kind.TWO))
    println(set.remove(Kind.TWO))
    println(set.joinToString(","))
    println(set.retainAll(setOf(Kind.THREE)))
    println(set.joinToString(","))
    set.add(Kind.ONE)
    val iterator = set.iterator()
    println(iterator.next())
    iterator.remove()
    println(set.joinToString(","))
    println(set.removeAll(setOf(Kind.THREE)))
    println(set.isEmpty())
    set.add(Kind.TWO)
    set.clear()
    println(set.size)

    val first: ModifierSet<Kind> = ModifierSet.noneOf(type)
    val second = EnumSet.noneOf(type)
    println(first === second)
    first.add(Kind.TWO)
    println(second.size)
    val erased: Any = first
    println(erased is EnumSet<*>)
    println(erased is MutableSet<*>)
    println(first == setOf(Kind.TWO))

    @Suppress("UNCHECKED_CAST")
    val unsafe = first as MutableSet<Any?>
    try {
        unsafe.add(Other.ONE)
    } catch (_: ClassCastException) {
        println("wrong enum")
    }
    try {
        unsafe.add(null)
    } catch (_: NullPointerException) {
        println("null element")
    }
    println(unsafe.contains(Other.ONE))
    println(unsafe.remove(null))
    println(first.joinToString(","))

    val absentType: java.lang.Class<Kind>? = null
    try {
        EnumSet.noneOf(absentType)
    } catch (_: NullPointerException) {
        println("null class")
    }
    @Suppress("UNCHECKED_CAST")
    val wrongType = Plain().javaClass as java.lang.Class<Kind>
    try {
        EnumSet.noneOf(wrongType)
    } catch (_: ClassCastException) {
        println("non-enum class")
    }
    val control = HashSet<Kind>()
    control.add(Kind.ONE)
    println(control.contains(Kind.ONE))
    println(control.remove(Kind.ONE))
    println(control.contains(Kind.ONE))
    val keys = hashMapOf(Kind.ONE to "one", Kind.TWO to "two")
    println(keys[Kind.ONE])
    println(keys.remove(Kind.ONE))
    println(keys[Kind.ONE])
}
