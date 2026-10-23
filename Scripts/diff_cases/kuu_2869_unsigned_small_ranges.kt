fun main() {
    for (i in 1u.toUByte() until 5u.toUByte()) print(i)
    println()
    for (i in 1u.toUShort() until 5u.toUShort()) print(i)
    println()

    for (i in 1u.toUByte()..5u.toUByte()) print(i)
    println()
    for (i in 1u.toUShort()..5u.toUShort()) print(i)
    println()

    for (i in 5u.toUByte() downTo 1u.toUByte()) print(i)
    println()
    for (i in 5u.toUShort() downTo 1u.toUShort()) print(i)
    println()

    for (i in 1u.toUByte()..<6u.toUByte() step 2) print(i)
    println()
    for (i in 1u.toUShort()..<6u.toUShort() step 2) print(i)
    println()
    for (i in 5u.toUByte() downTo 1u.toUByte() step 2) print(i)
    println()
    for (i in 5u.toUShort() downTo 1u.toUShort() step 2) print(i)
    println()
}
