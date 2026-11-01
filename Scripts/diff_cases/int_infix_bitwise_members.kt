// KUU-4103: `Int and Int` (and the other same-type bitwise infix members)
// must resolve against the public kotlin.* member surface — the generated
// JetBrains markdown lexers call `zzAttributes and 1 == 1` — instead of
// reaching bundled package-internal helpers such as kotlinx.io's
// `internal infix fun Int.and(other: Long)`.
fun main() {
    // Int infix bitwise members
    println(5 and 3)
    println(5 or 3)
    println(5 xor 3)
    println(5.inv())
    println(1 shl 3)
    println(16 shr 2)
    println(-1 ushr 28)

    // Long infix bitwise members
    println(5L and 3L)
    println(5L or 3L)
    println(5L xor 3L)
    println(5L.inv())
    println(1L shl 3)
    println(16L shr 2)
    println(-1L ushr 60)

    // Member-call (dot) forms
    println(5.and(3))
    println(5.or(3))
    println(5.xor(3))
    println(5L.and(3L))
    println(5.inv())

    // Unsigned infix bitwise members
    println(0xF0u and 0x0Fu)
    println(0xF0u or 0x0Fu)
    println(0xF0u xor 0x0Fu)
    println(0xF0u.inv())
    println(1u shl 3)
    println(16u shr 2)
    println(0xF0uL and 0x0FuL)
    println(1uL shl 3)
    println(16uL shr 2)
    println(0xF0uL.inv())

    // UByte / UShort infix bitwise members
    val ub: UByte = 0xF0u
    val vb: UByte = 0x0Fu
    println(ub and vb)
    println(ub or vb)
    println(ub xor vb)
    println(ub.inv())
    val us: UShort = 0xFF00u
    val vs: UShort = 0x00FFu
    println(us and vs)
    println(us or vs)
    println(us xor vs)
    println(us.inv())

    // Generated-lexer shape: local var + infix inside a compound condition
    var zzAttributes = 7
    if (zzAttributes and 1 == 1) println("accept") else println("reject")
    zzAttributes = zzAttributes and 0xFF
    while (zzAttributes and 1 == 0) {
        zzAttributes = zzAttributes shr 1
    }
    println(zzAttributes)

    // Boolean infix members
    println(true and false)
    println(true or false)
    println(true xor false)
}
