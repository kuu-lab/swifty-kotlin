fun main() {
    val topLevel = run { 41 }
    val receiver = "hello".run { length }
    val caught = "hello".runCatching { length + 1 }
    val failed = "hello".runCatching { throw RuntimeException("boom") }

    println("topLevel=$topLevel")
    println("receiver=$receiver")
    println("caught=" + caught.getOrThrow())
    println("failed=" + failed.isFailure)
}
