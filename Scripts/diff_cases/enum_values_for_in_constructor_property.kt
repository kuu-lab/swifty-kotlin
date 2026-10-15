enum class Dogs(val id: String) {
    BULLDOG("bulldog"), TERRIER("terrier"), HOUND("hound"), MASTIFF("mastiff")
}

fun main() {
    for (value in Dogs.values())
        println("${value.name} -> ${value.id}")
}
