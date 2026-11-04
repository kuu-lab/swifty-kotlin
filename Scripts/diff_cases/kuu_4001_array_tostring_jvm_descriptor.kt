// KUU-4001: array identity toString must spell the JVM array class
// descriptor (`[L<Element>;@` / `[X@` + lowercase hex identity hash),
// not `kotlin.Array@hash` / `kotlin.IntArray@hash`. The hash value is
// nondeterministic, so assertions check only the deterministic shape.

class Foo(val x: Int)

class Outer {
    class Inner
}

private fun jvmShape(rendered: String, prefix: String): Boolean {
    if (!rendered.startsWith(prefix)) return false
    val hash = rendered.substring(prefix.length)
    return hash.isNotEmpty() && hash.all { it in '0'..'9' || it in 'a'..'f' }
}

fun main() {
    val objects = arrayOf(1, 2)
    println(jvmShape(objects.toString(), "[Ljava.lang.Integer;@"))
    println(jvmShape("$objects", "[Ljava.lang.Integer;@"))
    val asAny: Any = objects
    println(jvmShape(asAny.toString(), "[Ljava.lang.Integer;@"))

    println(jvmShape(arrayOf("a", "b").toString(), "[Ljava.lang.String;@"))
    println(jvmShape(arrayOf(Foo(3)).toString(), "[LFoo;@"))
    println(jvmShape(arrayOf(Outer.Inner()).toString(), "[LOuter${'$'}Inner;@"))
    println(jvmShape(arrayOf<Any?>(1, "x", null).toString(), "[Ljava.lang.Object;@"))
    println(jvmShape(emptyArray<Int>().toString(), "[Ljava.lang.Integer;@"))
    println(jvmShape(arrayOfNulls<String>(2).toString(), "[Ljava.lang.String;@"))

    println(jvmShape(intArrayOf(1, 2).toString(), "[I@"))
    println(jvmShape(longArrayOf(1L).toString(), "[J@"))
    println(jvmShape(byteArrayOf(1).toString(), "[B@"))
    println(jvmShape(shortArrayOf(1).toString(), "[S@"))
    println(jvmShape(booleanArrayOf(true).toString(), "[Z@"))
    println(jvmShape(charArrayOf('a').toString(), "[C@"))
    println(jvmShape(IntArray(3).toString(), "[I@"))

    println(jvmShape(arrayOf(intArrayOf(1), intArrayOf(2)).toString(), "[[I@"))
    println(jvmShape(arrayOf(arrayOf("x")).toString(), "[[Ljava.lang.String;@"))

    // println(CharArray) resolves to the CharArray overload that prints the
    // characters, not the Any? overload that would render `[C@hash`.
    println(charArrayOf('o', 'k'))

    // Unsigned arrays are value classes: their generated toString renders
    // the storage contents, so it is deterministic.
    println(uintArrayOf(1u, 2u).toString() == "UIntArray(storage=[1, 2])")
    println(ulongArrayOf(1uL).toString() == "ULongArray(storage=[1])")
}
