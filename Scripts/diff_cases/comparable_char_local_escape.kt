fun compareComparable(value: Comparable<Char>): Int = value.compareTo('a')
fun mkCmp(): Comparable<Char> = 'z'

fun main() {
    // KUU-1211: a `Comparable<Char>` local that never escapes keeps kotlinc's
    // unboxed `char` slot, so `compareTo` reports the normalized -1/0/1 like
    // `Intrinsics.compare`. Once the local escapes to `Any`, the read is boxed
    // and `Comparable.compareTo` reports the raw UTF-16 code-unit difference.
    val unescaped: Comparable<Char> = 'z'
    println(unescaped.compareTo('a'))
    println(unescaped.compareTo('z'))
    println(unescaped.compareTo('x'))

    val escaped: Comparable<Char> = 'z'
    println(escaped.compareTo('a'))
    println(escaped)
    println(compareComparable(escaped))

    // The copy-connected component shares one slot on the JVM: an escape
    // through either variable boxes both reads.
    val copySource: Comparable<Char> = 'z'
    val copyTarget = copySource
    println(copySource.compareTo('a'))
    println(copyTarget.compareTo('a'))
    println(copyTarget)

    // A `Comparable<Char>?` local can stay unboxed too; `?.` and `!!` receivers
    // are non-escaping reads.
    val nullable: Comparable<Char>? = 'z'
    println(nullable?.compareTo('a'))
    val asserted: Comparable<Char>? = 'z'
    println(asserted!!.compareTo('a'))

    // An initializer that is not `Char`-typed keeps the boxed representation
    // even when the local never escapes.
    val fromCall: Comparable<Char> = mkCmp()
    println(fromCall.compareTo('a'))

    // `when` subjects and equality operands are non-escaping reads.
    val inWhen: Comparable<Char> = 'z'
    println(inWhen.compareTo('a'))
    when (inWhen) { 'z' -> println("isz") else -> println("no") }
    val inEquality: Comparable<Char> = 'z'
    println(inEquality.compareTo('a'))
    println(inEquality == 'z')

    // Escaping reads: `===`, string templates, `in`, elvis, lambda capture.
    val identity: Comparable<Char> = 'z'
    println(identity.compareTo('a'))
    println(identity === 'z')

    val templated: Comparable<Char> = 'z'
    println(templated.compareTo('a'))
    println("v=$templated")

    val captured: Comparable<Char> = 'z'
    println(captured.compareTo('a'))
    val lam = { println(captured) }
    lam()
}
