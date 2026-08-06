fun main() {
    // Int.rotateLeft
    println(1.rotateLeft(0))
    println(1.rotateLeft(1))
    println(1.rotateLeft(31))
    println(1.rotateLeft(32))
    println(1.rotateLeft(33))
    println(1.rotateLeft(-1))
    println((-1).rotateLeft(5))
    println(Int.MAX_VALUE.rotateLeft(1))
    println(Int.MIN_VALUE.rotateLeft(1))
    println(0x12345678.rotateLeft(8))

    // Int.rotateRight
    println(1.rotateRight(0))
    println(1.rotateRight(1))
    println(1.rotateRight(31))
    println(1.rotateRight(32))
    println(1.rotateRight(33))
    println(1.rotateRight(-1))
    println((-1).rotateRight(5))
    println(Int.MAX_VALUE.rotateRight(1))
    println(Int.MIN_VALUE.rotateRight(1))
    println(0x12345678.rotateRight(8))

    // Long.rotateLeft
    println(1L.rotateLeft(0))
    println(1L.rotateLeft(1))
    println(1L.rotateLeft(63))
    println(1L.rotateLeft(64))
    println(1L.rotateLeft(65))
    println(1L.rotateLeft(-1))
    println((-1L).rotateLeft(5))
    println(Long.MAX_VALUE.rotateLeft(1))
    println(Long.MIN_VALUE.rotateLeft(1))
    println(0x123456789ABCDEFL.rotateLeft(8))

    // Long.rotateRight
    println(1L.rotateRight(0))
    println(1L.rotateRight(1))
    println(1L.rotateRight(63))
    println(1L.rotateRight(64))
    println(1L.rotateRight(65))
    println(1L.rotateRight(-1))
    println((-1L).rotateRight(5))
    println(Long.MAX_VALUE.rotateRight(1))
    println(Long.MIN_VALUE.rotateRight(1))
    println(0x123456789ABCDEFL.rotateRight(8))

    // round-trip and variable receivers
    val x = 0x0F0F0F0F
    println(x.rotateLeft(4).rotateRight(4))
    val y = 0x0F0F0F0F0F0F0F0FL
    println(y.rotateRight(12).rotateLeft(12))
}
