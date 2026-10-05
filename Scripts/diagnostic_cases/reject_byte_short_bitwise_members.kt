// EXPECT-REJECT
fun rejected(b: Byte, s: Short, nb: Byte?, ns: Short?) {
    b and b
    b or b
    b xor b
    b.and(b)
    b.or(b)
    b.xor(b)
    b.inv()
    s and s
    s or s
    s xor s
    s.and(s)
    s.or(s)
    s.xor(s)
    s.inv()
    nb?.and(b)
    nb?.or(b)
    nb?.xor(b)
    nb?.inv()
    ns?.and(s)
    ns?.or(s)
    ns?.xor(s)
    ns?.inv()
    b shl 1
    b shr 1
    b ushr 1
    s shl 1
    s shr 1
    s ushr 1
}
