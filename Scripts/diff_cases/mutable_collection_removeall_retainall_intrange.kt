fun main() {
    val removeRange = mutableListOf(1, 2, 3, 4, 5, 6)
    println(removeRange.removeAll(2..4))
    println(removeRange)
    println(removeRange.removeAll(2..4))
    println(removeRange)

    val retainRange = mutableListOf(1, 2, 3, 4, 5, 6)
    println(retainRange.retainAll(2..4))
    println(retainRange)

    val evenProgression: IntProgression = 2..6 step 2
    val removeProgression = mutableListOf(1, 2, 3, 4, 5, 6)
    println(removeProgression.removeAll(evenProgression))
    println(removeProgression)

    val retainProgression = mutableListOf(1, 2, 3, 4, 5, 6)
    println(retainProgression.retainAll(evenProgression))
    println(retainProgression)

    val removeSet = linkedSetOf(1, 2, 3, 4, 5, 6)
    println(removeSet.removeAll(2..4))
    println(removeSet)

    val retainSet = linkedSetOf(1, 2, 3, 4, 5, 6)
    println(retainSet.retainAll(2..4))
    println(retainSet)

    val retainEmptyRange = mutableListOf(1, 2, 3)
    println(retainEmptyRange.retainAll(2..1))
    println(retainEmptyRange)
}
