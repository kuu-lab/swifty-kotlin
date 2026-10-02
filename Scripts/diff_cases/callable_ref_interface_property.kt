// A property reference through an interface must dispatch the getter through
// the itable for every implementer instead of calling the declaring stub.
interface Named { val label: String }
enum class Dir : Named { N, S; override val label get() = name.lowercase() + "!" }
class Person(override val label: String) : Named
class Computed(val n: Int) : Named { override val label: String get() = "c$n" }

fun main() {
    println(Dir.entries.map { it.label })
    println(Dir.entries.map(Dir::label))
    println(listOf(Person("a"), Person("b")).map(Named::label))
    println(listOf(Computed(1), Computed(2)).map(Named::label))
    val ref = Named::label
    println(ref.get(Computed(3)))
    println(ref.get(Person("p")))
    val bound = Person("bound")::label
    println(bound.get())
}
