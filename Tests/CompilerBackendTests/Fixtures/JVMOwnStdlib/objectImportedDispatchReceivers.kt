import Factories.next as nextValue
import Factories.inherited as inheritedValue
import Initializer.read as importedRead

open class FactoryBase {
    private var inheritedCount = 0
    fun inherited(step: Int = 2): Int { inheritedCount += step; return inheritedCount }
}
object Factories : FactoryBase() {
    private var count = 10
    fun next(step: Int = 1): Int { count += step; return count }
}
object Initializer {
    private var value = 7
    val initial = importedRead()
    fun read(): Int = value
}
fun Factories?.readNullable(): Int = nextValue()
fun Factories?.readInherited(): Int = inheritedValue()
fun String.readImported(): Int = nextValue(3)
class Reader { fun read(): Int = nextValue(2) }
fun shadow(): Int { val nextValue: () -> Int = { 99 }; return nextValue() }
fun main() {
    val nullable: Factories? = null
    println(nullable.readNullable())
    println(nullable.readInherited())
    println(Factories.readNullable())
    println(Factories.readInherited())
    println("receiver".readImported())
    println(Reader().read())
    println(nullable?.next())
    println(Factories.next())
    println(shadow())
    println(Initializer.initial)
}
