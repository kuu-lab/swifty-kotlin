// EXPECT-REJECT
fun rejected(ub: UByte, us: UShort, ui: UInt, ul: ULong,
             nb: UByte?, ns: UShort?, ni: UInt?, nl: ULong?) {
    -1u
    -1uL
    -4294967296u
    -0xFFFFFFFFu
    -(1u)
    -1u.toUByte()
    -1u.toUShort()
    -ub
    -us
    -ui
    -ul
    -nb
    -ns
    -ni
    -nl
    +1u
    +1uL
    +ub
    +us
    +ui
    +ul
    val narrowByte: UByte = -1u
    val narrowShort: UShort = -1u
}
