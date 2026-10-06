fun main() {
    println((null as List<Int>?).orEmpty())
    println((null as Map<String, Int>?).orEmpty())
    println((null as? List<Int>?).orEmpty())
}
