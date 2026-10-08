// KUU-1463: `is` smart-casts of stable member properties work inside lazy lambdas.
class D<R>(val defaultValue: R?) {
    val defaultValueSet by lazy {
        defaultValue != null && (defaultValue is List<*> && defaultValue.isNotEmpty() || defaultValue !is List<*>)
    }

    val explicitDefaultValueSet by lazy {
        this.defaultValue != null && (this.defaultValue is List<*> && this.defaultValue.isNotEmpty() || this.defaultValue !is List<*>)
    }
}

fun main() {
    println("${D<List<Int>>(listOf(1, 2)).defaultValueSet}:${D<List<Int>>(listOf(1, 2)).explicitDefaultValueSet}")
    println("${D<List<Int>>(emptyList()).defaultValueSet}:${D<List<Int>>(emptyList()).explicitDefaultValueSet}")
    println("${D<Int>(5).defaultValueSet}:${D<Int>(5).explicitDefaultValueSet}")
    println("${D<Int?>(null).defaultValueSet}:${D<Int?>(null).explicitDefaultValueSet}")
}
