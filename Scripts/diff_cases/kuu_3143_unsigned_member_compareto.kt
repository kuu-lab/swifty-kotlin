// KUU-3143: member-call compareTo on unsigned primitives and UIntArray.max()
// must resolve against the primitive class symbol even though `fun UInt(...)`,
// `fun ULong(...)`, `fun UByte(...)`, and `fun UShort(...)` share their
// kotlin.* FQ names.
@OptIn(ExperimentalUnsignedTypes::class)
fun main() {
    println(1u.compareTo(2u))
    println(1uL.compareTo(2uL))
    println(1.toUByte().compareTo(2.toUByte()))
    println(1.toUShort().compareTo(2.toUShort()))
    println(1u < 2u)
    println(uintArrayOf(1u, 2u).max())
    println(uintArrayOf(1u, 2u).min())
}
