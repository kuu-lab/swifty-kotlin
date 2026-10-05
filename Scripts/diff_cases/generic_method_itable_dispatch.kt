interface GenericProbe {
    fun <T> probe(values: List<T>): Int = 1
    fun <T> transform(operation: (T) -> T): Int = 2
}

class DefaultProbe : GenericProbe

class CustomProbe : GenericProbe {
    override fun <T> probe(values: List<T>): Int = 7
    fun <T> probe(values: Set<T>): Int = 9
    override fun <T> transform(operation: (T) -> T): Int = 8
}

interface GenericContainer<T> {
    fun inspect(values: List<T>): Int = 3
}

class IntContainer : GenericContainer<Int> {
    override fun inspect(values: List<Int>): Int = 11
}

fun main() {
    val original: GenericProbe = DefaultProbe()
    val custom: GenericProbe = CustomProbe()
    val container: GenericContainer<Int> = IntContainer()
    println(original.probe(listOf(2)))
    println(custom.probe(listOf(2)))
    println(custom.transform<Int> { it })
    println(CustomProbe().probe(setOf(2)))
    println(container.inspect(listOf(2)))
}
