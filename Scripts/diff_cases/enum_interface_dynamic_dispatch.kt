// BUG-B: an enum class implementing an interface must support dynamic
// (itable) dispatch through an interface-typed reference to a property whose
// getter reads the enum's own implicit receiver (name/ordinal/constructor
// properties) -- not just direct access on the concrete enum type.
interface Named { val label: String }
enum class Dir : Named { N, S; override val label get() = name.lowercase() + "!" }

fun main() {
    println(Dir.N.label)
    val nm: Named = Dir.S
    println(nm.label)
}
