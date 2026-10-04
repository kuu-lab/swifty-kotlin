package golden.diff

@kotlin.ExperimentalUnsignedTypes
annotation class MyUnsignedMarker

@MyUnsignedMarker
fun markedFun(): Unit {
}

@OptIn(kotlin.ExperimentalUnsignedTypes::class)
fun main() {
    markedFun()
    println("stdlib_kotlin_n_ExperimentalUnsignedTypes ok")
}
