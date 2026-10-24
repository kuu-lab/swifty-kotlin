// A value class wrapping a nullable reference (String?) erases to its payload
// type, so a non-null wrapper holding a null payload must NOT be conflated with
// Kotlin null at V?/Any/generic boundaries: `V(null) == null` is false,
// `V(null) != null` is true, `v?.x` reads the payload, and the wrapper prints
// as `V(x=null)`. Previously the `V` -> `V?` boundary stored the bare payload
// pointer, so `V(null)` collapsed into the null sentinel.
@JvmInline
value class V(val x: String?) {
    fun tag(): String = "V(" + (x ?: "<null>") + ")"
}

@JvmInline
value class V2(val x: V)

interface HasName {
    fun name(): String
}

@JvmInline
value class VI(val s: String?) : HasName {
    override fun name(): String = "VI:<" + (s ?: "null") + ">"
}

fun show(v: V?) {
    println(v?.x)
    println(v == null)
    println((v ?: V("fallback")).x)
    println(v)
}

fun wrap(v: V?): V? = v
fun unwrap(v: V?): V = v!!
fun makeNullableBox(): V? = V(null)

fun main() {
    show(V("a"))
    show(V(null))
    show(null)

    val n: V? = V(null)
    println(n?.x)
    println(n == null)
    println(n != null)

    val a: Any = V(null)
    println(a is V)
    println(a)
    println(V(null) == V(null))
    println(V(null) == null)
    println(V("q") == V("q"))
    println(V("q") == V("r"))
    println(V(null) != V("q"))

    var v: V? = V(null)
    println(v?.tag())
    v = V("z")
    println(v?.tag())
    if (v != null) println(v.x)
    println(unwrap(v).x)
    println(wrap(V(null)))
    println(makeNullableBox())

    val casted: Any = V("c")
    println(casted as V)
    println((casted as? V)?.x)

    val list = listOf(V(null), V("p"), null)
    println(list.size)
    println(list[0])
    println(list[1])
    println(list[2])
    println(list[0] == null)

    val vi: HasName = VI(null)
    println(vi is VI)
    println(vi.name())
    println(VI(null))

    var n2: V2? = V2(V(null))
    println(n2 == null)
    println(n2?.x)
    println(n2?.x?.x)
    n2 = null
    println(n2 == null)
    n2 = V2(V("y"))
    println(n2?.x?.x)
}
