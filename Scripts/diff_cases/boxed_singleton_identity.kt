// KUU-2957: boxed singleton identity — ===/== across Any/Any? boundaries.
// Unit, Boolean, Char, enum entries and JVM-cached primitives must keep
// singleton identity when boxed through Any.

enum class E { A, B, C }
enum class F { A, B }

fun bar(): Unit {}
fun baz(): Any? = bar()
fun quux(): Unit? = bar()

data class D(val v: E)

fun main() {
    // JetBrains unit/kt4212.kt
    if (baz() != quux()) { println("Fail"); return }

    // Unit identity across Any/Any?/Unit? representations
    val u: Unit = bar()
    val ua: Any = u
    val uq: Unit? = bar()
    println(ua === Unit)
    println(baz() == quux())
    println(uq === Unit)
    println(uq === ua)
    println((u as Any) === (Unit as Any))

    // Boolean singleton
    fun boolCheck(x: Any) = x === true
    println(boolCheck(true))
    val b: Boolean = true
    val ba: Any = b
    println(ba === b)

    // Char identity cache
    val c: Char = 'a'
    val ca: Any = c
    println(ca === c)
    println(('\u007F' as Any) === ('\u007F' as Any))   // cached
    println(('\u0080' as Any) === ('\u0080' as Any))   // uncached -> false

    // Primitive cache boundaries
    println((127 as Any) === (127 as Any))             // cached -> true
    println((128 as Any) === (128 as Any))             // uncached -> false
    println((-128 as Any) === (-128 as Any))           // cached -> true
    println((-129 as Any) === (-129 as Any))           // uncached -> false
    println((127L as Any) === (127L as Any))           // Long cache -> true
    println((1000L as Any) === (1000L as Any))         // uncached -> false

    // Enum identity through Any
    val e: E = E.A
    val e2: E? = E.A
    val en: E? = null
    val a: Any = E.A
    println(a === e)             // erased box vs enum ref
    println(a === ga())          // repeated Any boxing -> same entry box
    println(e2 === a)            // nullable enum vs Any box
    println(e2 == a)             // == variant
    println(en === a)            // null vs box -> false
    println(e2 == null)          // false
    println(en == null)          // true
    println((e as Any) == f())   // different enum class -> false

    // Collections
    val l = listOf(E.A, E.B)
    println(l[0] === E.A)
    println(l.contains(E.A))
    println(l.contains(e2))
    println(mapOf(E.A to 1)[E.A])
    println(setOf(E.A, E.A, E.B).size)
    println(E.values()[0] === E.A)
    println(E.entries[0] === E.A)
    println(E.valueOf("A") === E.A)
    println(listOf(E.A) == listOf(E.A))
    println(listOf(E.A) == listOf(E.B))

    // when on non-null and nullable subjects
    println(when (e) { E.A -> "a"; else -> "other" })
    println(when (e2) { E.A -> "a"; else -> "other" })
    println(when (en) { E.A -> "a"; null -> "null"; else -> "other" })

    // data class equality with enum property
    println(D(E.A) == D(E.A))
}

fun ga(): Any = E.A
fun f(): F = F.A
