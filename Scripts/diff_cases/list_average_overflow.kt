fun main() {
    println(listOf(Int.MAX_VALUE, Int.MAX_VALUE).average())
    println(listOf(2_000_000_000, 2_000_000_000, 2_000_000_000).average())
    println(setOf(Int.MAX_VALUE, Int.MAX_VALUE - 1).average())
    println(listOf(Long.MAX_VALUE, Long.MAX_VALUE).average())
    println(listOf<Short>(Short.MAX_VALUE, Short.MAX_VALUE).average())
    println(listOf<Byte>(Byte.MAX_VALUE, Byte.MAX_VALUE).average())
}
