fun compareChars(lhs: Char, rhs: Char): Int = lhs.compareTo(rhs)

fun <T : Comparable<T>> compareGeneric(lhs: T, rhs: T): Int = lhs.compareTo(rhs)

fun compareComparable(lhs: Comparable<Char>, rhs: Char): Int = lhs.compareTo(rhs)

fun asComparable(value: Char): Comparable<Char> = value

fun main() {
    println('z'.compareTo('a'))
    println('a'.compareTo('z'))
    println('a'.compareTo('a'))
    println(Char.MAX_VALUE.compareTo(Char.MIN_VALUE))
    println(Char.MIN_VALUE.compareTo(Char.MAX_VALUE))
    println(Char.MIN_VALUE.compareTo(Char.MIN_VALUE))
    println(Char.MAX_VALUE.compareTo(Char.MAX_VALUE))

    println(compareChars('\u7FFF', '\u8000'))
    println(compareChars('\u8000', '\u7FFF'))
    println(compareChars('\uD800', '\uDC00'))
    println(compareChars('\uDFFF', '\uD800'))
    println(compareChars('\uD800', '\uD800'))
    println(compareChars('\uDFFF', '\uE000'))
    println(compareChars('\uFFFF', '\uE000'))

    val nullable: Char? = 'z'
    println(nullable?.compareTo('a'))
    val missing: Char? = null
    println(missing?.compareTo('a'))
    val comparable: Comparable<Char> = asComparable('z')
    println(comparable.compareTo('a'))
    println(comparable)
    println(compareComparable(comparable, 'a'))
    println(compareGeneric('z', 'a'))
    println(compareGeneric('a', 'z'))
    println(compareGeneric(Char.MAX_VALUE, Char.MIN_VALUE))
    println(compareGeneric(Char.MIN_VALUE, Char.MAX_VALUE))
    println(compareGeneric('\uD800', '\uD800'))
    println(compareComparable('z', 'a'))
    println(compareComparable('a', 'z'))
    println(compareGeneric(122, 97))

    val erased: Any = 'z'
    println((erased as Char).code)
    println((erased as Char).compareTo('a'))

    println('z' - 'a')
    println('a' - 'z')
    println(Char.MAX_VALUE - Char.MIN_VALUE)
    println(Char.MIN_VALUE - Char.MAX_VALUE)
    println('a' < 'z')
    println('z' > 'a')
    println('a' <= 'a')
    println('a' >= 'a')
}
