import kotlin.reflect.KClass

fun name(value: Any): String? = value::class.simpleName

fun check(value: Any, expected: KClass<*>) {
    val actual = value::class
    println(actual.simpleName)
    println(actual.qualifiedName)
    println(actual == expected)
    println(actual === expected)
    println(actual.isInstance(value))
}

fun main() {
    println(name(1..2))
    // The first erased lookup runs before an explicit IntRange class literal.
    val first: Any = 1..2
    val firstClass = first::class
    println(firstClass.simpleName)
    println(firstClass.qualifiedName)
    println(firstClass == IntRange::class)
    println(firstClass === IntRange::class)
    println((1..2)::class.simpleName)
    println((1..2)::class.qualifiedName)
    println((1..2)::class === IntRange::class)
    check(1..2, IntRange::class)
    check(2 downTo 1, IntProgression::class)
    check(1L..2L, LongRange::class)
    check(2L downTo 1L, LongProgression::class)
    check('a'..'b', CharRange::class)
    check('b' downTo 'a', CharProgression::class)
    check(1u..2u, UIntRange::class)
    check(2u downTo 1u, UIntProgression::class)
    check(1uL..2uL, ULongRange::class)
    check(2uL downTo 1uL, ULongProgression::class)
    check(2..1, IntRange::class)
    check((1..3) step 2, IntProgression::class)
    val number: Any = 42
    println(number::class.simpleName)
    println(number::class.qualifiedName)
    println(number::class == Int::class)
    val string: Any = "control"
    println(string::class.simpleName)
    println(string::class.qualifiedName)
    println(string::class == String::class)
}
