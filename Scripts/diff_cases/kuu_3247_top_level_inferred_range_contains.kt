val inferredCharRange = '1'..'3'
val inferredIntRange = 1..3

fun main() {
    val localCharRange = '1'..'3'
    val localIntRange = 1..3
    val explicitCharRange: CharRange = CharRange('1', '3')
    val explicitIntRange: IntRange = IntRange(1, 3)
    val passed =
        inferredCharRange.contains('2') && !inferredCharRange.contains('9') &&
        '2' in inferredCharRange && '9' !in inferredCharRange &&
        inferredIntRange.contains(2) && !inferredIntRange.contains(9) &&
        2 in inferredIntRange && 9 !in inferredIntRange &&
        explicitCharRange.contains('2') && explicitIntRange.contains(2) &&
        ('1'..'3').contains('2') && (1..3).contains(2) &&
        localCharRange.contains('2') && localIntRange.contains(2)
    println(if (passed) "OK" else "FAIL")
}
