class Bug219Sample(val suffix: String) {
    fun decorate(): String = "decorated:$suffix"
    fun describeList(): List<String> = listOf(suffix)
}

fun <T, R> bug219Apply(value: T, block: (T) -> R): R = block(value)

fun <T, R> bug219ApplyWithRelatedType(value: T, fallback: R, block: (T) -> R): R = block(value)

fun <T, R> bug219NestedApply(value: T, block: (T) -> R): R = bug219Apply(value) { item -> block(item) }

fun <R> bug219ApplyWithRelatedReturn(block: () -> List<R>): List<R> = block()

fun <R> bug219ApplyWithRelatedNestedType(value: R, block: (R) -> List<R>): List<R> = block(value)

fun main() {
    println(bug219Apply("hello") { it.uppercase() })
    println(bug219Apply("hello") { it.length })
    val sample = Bug219Sample("x")
    println(bug219Apply(sample) { it.decorate() })
    println(bug219Apply(1) { it.plus(1) })

    val increment: (Int) -> Int = { it.plus(1) }
    println(bug219Apply(1) { increment(it) })

    println(bug219ApplyWithRelatedType("hello", 0) { it.length })
    println(bug219ApplyWithRelatedReturn { sample.describeList() })
    println(bug219ApplyWithRelatedNestedType("hello") { sample.describeList() })
    println(bug219NestedApply("hello") { it.uppercase() })
}
