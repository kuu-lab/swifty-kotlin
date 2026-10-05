package genericrefs

class Box<T> {
    fun echo(value: Int): Int = value
    fun identity(value: T): T = value
}

class Outer {
    class Nested<T> {
        fun echo(value: Int): Int = value + 1
    }
}

class Stored<T>(val value: T)

typealias Alias<T> = Box<T>

fun Box<String>.extended(value: Int): Int = value + 2

fun main() {
    val ref: (Box<String>, Int) -> Int = Box<String>::echo
    println(ref(Box<String>(), 42))

    val inferred = Box<String>::identity
    println(inferred(Box<String>(), "typed"))
    val integer = Box<Int>::identity
    println(integer(Box<Int>(), 7))

    val qualified = genericrefs.Box<String>::echo
    println(qualified(Box<String>(), 43))
    val nested = Outer.Nested<String>::echo
    println(nested(Outer.Nested<String>(), 43))
    val nestedArgs = Box<List<String?>>::echo
    println(nestedArgs(Box<List<String?>>(), 45))
    val star = Box<*>::echo
    println(star(Box<Int>(), 46))
    val projected = Box<out String>::echo
    println(projected(Box<String>(), 47))
    val alias = Alias<String>::identity
    println(alias(Box<String>(), "alias"))
    val extension = Box<String>::extended
    println(extension(Box<String>(), 46))
    val property = Stored<String>::value
    println(property.get(Stored<String>("property")))

    val bound = Box<String>()::echo
    println(bound(49))
    val a = 1
    val b = 2
    println(a < b && b > a)
}
