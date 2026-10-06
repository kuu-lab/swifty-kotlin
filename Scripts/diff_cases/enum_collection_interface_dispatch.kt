// Enum entries stored through an Any-erased collection/vararg boundary must
// keep their interface itable (property getters and methods), not only a
// direct `val h: HasCode = St.NF` conversion.
interface HasCode {
    val code: Int
    fun describe(): String
}

enum class St(override val code: Int) : HasCode {
    OK(200),
    NF(404);

    override fun describe(): String = "$name=$code"
}

interface Shape {
    fun label(): String
    fun scaled(by: Int): Int = by
}

enum class Sq(val side: Int) : Shape {
    A(2) {
        override fun label(): String = "a!"
    },
    B(5);

    override fun label(): String = "base"
    override fun scaled(by: Int): Int = side * by
}

interface Computed {
    val v: Int
    val w: String
}

enum class Cp : Computed {
    X, Y;

    override val v: Int get() = ordinal * 10
    override val w: String = "w$ordinal"
}

fun codesOf(vararg items: HasCode): List<Int> = items.map { it.code }

fun main() {
    val codes: List<HasCode> = listOf(St.OK, St.NF)
    println(codes.map { it.code })
    println(codes.map { it.describe() })

    val set: Set<HasCode> = setOf(St.NF)
    println(set.map { it.code })

    val mutable = mutableListOf<HasCode>(St.OK)
    mutable.add(St.NF)
    println(mutable.map { it.code })

    val array: Array<HasCode> = arrayOf(St.NF, St.OK)
    println(array.map { it.code })

    println(codesOf(St.OK, St.NF))

    val shapes: List<Shape> = listOf(Sq.A, Sq.B)
    println(shapes.map { it.label() })
    println(shapes.map { it.scaled(3) })

    val computed: List<Computed> = listOf(Cp.X, Cp.Y)
    println(computed.map { it.v })
    println(computed.map { it.w })

    val direct: HasCode = St.NF
    println(direct.code)
    println(St.values().map { it.code })
    println(St.entries.map { it.describe() })
}
