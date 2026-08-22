// BUG-170: comparison operators on an erased `T : Comparable<T>` receiver are
// lowered to the runtime `kk_compare_any` entry point. It used to require both
// operands to have the exact same runtime type, so user-defined Comparable
// implementations whose dynamic types differ (subclass vs base, or siblings
// sharing a Comparable interface) fell back to raw heap-address comparison
// instead of dispatching to `compareTo`.
//
// BUG-223: the Bronze/Gold path (compareTo only as Ranked's interface default)
// additionally needs the Ranked → Comparable type-graph edge and Ranked's
// default method in Comparable's itable. Both halves are covered here.

interface Ranked : Comparable<Ranked> {
    val rank: Int
    override fun compareTo(other: Ranked): Int = rank.compareTo(other.rank)
}

class Bronze : Ranked {
    override val rank: Int = 1
}

class Gold : Ranked {
    override val rank: Int = 3
}

open class Animal : Comparable<Animal> {
    open fun weight(): Int = 10
    override fun compareTo(other: Animal): Int = weight().compareTo(other.weight())
}

class Elephant : Animal() {
    override fun weight(): Int = 100
}

fun <T : Comparable<T>> maxOfTwo(a: T, b: T): T = if (a >= b) a else b

fun main() {
    val bronze: Ranked = Bronze()
    val gold: Ranked = Gold()
    println(maxOfTwo(bronze, gold).rank)
    println(maxOfTwo(gold, bronze).rank)
    println(bronze < gold)
    println(gold <= bronze)

    val animal: Animal = Animal()
    val elephant: Animal = Elephant()
    println(maxOfTwo(animal, elephant).weight())
    println(maxOfTwo(elephant, animal).weight())
    println(animal < elephant)
    println(elephant < animal)

    println(maxOfTwo(3, 7))
    println(maxOfTwo("apple", "banana"))
}
