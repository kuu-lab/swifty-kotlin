// EXPECT-STDOUT: 22
// EXPECT-STDOUT: 2
// EXPECT-STDOUT: 17
// EXPECT-STDOUT: 42
// EXPECT-STDOUT: 21
class Kuu2278IndexedBox(val value: Int)
class Kuu2278AssignedBox(var value: Int)
class Kuu2278MemberIndexedBox {
    operator fun get(index: Int): Int = index + 7
}
class Kuu2278MemberAssignedBox(var value: Int) {
    operator fun plusAssign(delta: Int) {
        value += delta * 10
    }
}
class Kuu2278FallbackBox
class Kuu2278FallbackAssignedBox(var value: Int)

operator fun Kuu2278FallbackBox.get(index: Int): Int = index + 41
operator fun Kuu2278FallbackAssignedBox.plusAssign(delta: Int) {
    value += delta * 20
}

fun localIndexedExtension(): Int {
    operator fun Kuu2278IndexedBox.get(index: Int): Int = index * value
    val indexed = Kuu2278IndexedBox(11)
    check(indexed.get(2) == 22)
    return indexed[2]
}

fun localPlusAssignExtension(): Int {
    operator fun Kuu2278AssignedBox.plusAssign(delta: Int) {
        value += delta
    }
    val explicit = Kuu2278AssignedBox(1)
    explicit.plusAssign(0)
    val assigned = Kuu2278AssignedBox(1)
    assigned += 1
    return assigned.value
}

fun localOperatorKeepsMemberPriority(): Int {
    operator fun Kuu2278MemberIndexedBox.get(index: Int): Int = index + 99
    operator fun Kuu2278MemberAssignedBox.plusAssign(delta: Int) {
        value += delta
    }
    val indexed = Kuu2278MemberIndexedBox()
    val assigned = Kuu2278MemberAssignedBox(0)
    assigned += 1
    return indexed[0] + assigned.value
}

fun localInapplicableOperatorFallsBack(): Int {
    operator fun Kuu2278FallbackBox.get(index: String): Int = 99
    return Kuu2278FallbackBox()[1]
}

fun localInapplicablePlusAssignFallsBack(): Int {
    operator fun Kuu2278FallbackAssignedBox.plusAssign(delta: String) {
        value += 100
    }
    val assigned = Kuu2278FallbackAssignedBox(1)
    assigned += 1
    return assigned.value
}

fun main() {
    println(localIndexedExtension())
    println(localPlusAssignExtension())
    println(localOperatorKeepsMemberPriority())
    println(localInapplicableOperatorFallsBack())
    println(localInapplicablePlusAssignFallsBack())
}
