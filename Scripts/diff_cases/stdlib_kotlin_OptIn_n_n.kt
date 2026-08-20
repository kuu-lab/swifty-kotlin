@RequiresOptIn
annotation class FirstMarker

@RequiresOptIn
annotation class SecondMarker

@OptIn(FirstMarker::class, SecondMarker::class)
fun main() {
    println("ok")
}
