class Box {
    val size: Int
        get() = 5

    fun readImplicit(): Int = size
    fun readExplicit(): Int = this.size
}

class Bag {
    val size: Int = 7
    val isEmpty: Boolean = false

    fun readImplicit(): Int = size
    fun readEmptyImplicit(): Boolean = isEmpty
}

fun main() {
    val box = Box()
    println(box.readImplicit())
    println(box.readExplicit())
    println(box.size)

    val bag = Bag()
    println(bag.readImplicit())
    println(bag.readEmptyImplicit())
    println(bag.size)
    println(bag.isEmpty)
}
