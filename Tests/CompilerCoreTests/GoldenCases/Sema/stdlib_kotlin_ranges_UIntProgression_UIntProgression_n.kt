fun inspectUIntProgression(progressions: List<UIntProgression>) {
    for (progression in progressions) {
        println("${progression.first},${progression.last},${progression.step}")
        println(progression.toString())
        println(progression.hashCode())
        println(progression == progressions.first())
    }
}
