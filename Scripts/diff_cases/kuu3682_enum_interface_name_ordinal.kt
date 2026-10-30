// KUU-3682: an enum implementing an interface that inherits `name`/`ordinal`
// registers its compiler-provided property accessors in the box's itable.
// Those accessors have no source KIR body, so the interface table used to
// reference an undefined `__itable_impl_<id>` symbol and fail to link.
interface Named { val name: String }
interface HasOrdinal { val ordinal: Int }
interface Both { val name: String; val ordinal: Int }

enum class E : Named { OK, KO }
enum class F : HasOrdinal { A, B }
enum class G : Both { X }

fun getName(n: Named) = n.name
fun getOrdinal(o: HasOrdinal) = o.ordinal

fun main() {
    // Interface-dispatched reads of the compiler-provided members.
    val n: Named = E.OK
    println(n.name)
    println(getName(E.KO))
    val o: HasOrdinal = F.B
    println(o.ordinal)
    println(getOrdinal(F.A))
    val b: Both = G.X
    println("${b.name}:${b.ordinal}")

    // Direct reads on the static enum type keep the lowered helper path.
    println(E.OK.name)
    println(E.KO.ordinal)

    // A normal class implementing the same interfaces is unaffected.
    println(getName(Plain("plain")))
}

class Plain(override val name: String) : Named
