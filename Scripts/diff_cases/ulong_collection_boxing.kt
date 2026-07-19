fun main() {
    val big: ULong = 17663719463477156090uL
    val small: ULong = 5uL

    println(listOf(big, small))
    println(setOf(big, small))
    println(mapOf("big" to big, "small" to small))

    val list = listOf(big, small)
    println(list.contains(big))
    println(list.contains(6uL))
    println(list == listOf(big, small))

    println(listOf(small, big).sorted())
    println(listOf(big, small).sorted())

    val dedup = setOf(big, big, small)
    println(dedup.size)
}
