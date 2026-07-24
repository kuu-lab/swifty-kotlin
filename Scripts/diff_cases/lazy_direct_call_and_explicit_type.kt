fun main() {
    val direct = lazy { 42 }
    println(direct.value)

    val explicitlyTyped: Lazy<Int> = lazyOf(99)
    println(explicitlyTyped.value)

    val ofValue = lazyOf(7)
    println(ofValue.value)
}
