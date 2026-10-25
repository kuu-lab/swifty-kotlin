// KUU-3074: expose the enum declaration class through Kotlin's supported JVM property.
enum class Direction {
    NORTH,
    SOUTH {
        override fun toString(): String = "south"
    }
}

fun <E : Enum<E>> declaringSimpleName(value: E): String = value.declaringJavaClass.simpleName

fun main() {
    println(Direction.NORTH.declaringJavaClass.simpleName)
    println(Direction.SOUTH.declaringJavaClass.simpleName)
    println(declaringSimpleName(Direction.SOUTH))
}
