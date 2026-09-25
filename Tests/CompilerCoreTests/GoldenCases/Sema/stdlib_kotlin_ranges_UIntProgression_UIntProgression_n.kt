fun inspectUIntProgression(progressions: List<UIntProgression>) {
    val progression = progressions.first()
    println("${progression.first},${progression.last},${progression.step}")
    println(progression.toString())
    println(progression.hashCode())
    println(progression == progressions.first())
}
