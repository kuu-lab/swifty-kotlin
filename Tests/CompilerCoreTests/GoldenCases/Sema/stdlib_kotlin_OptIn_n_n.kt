package golden.sema

@kotlin.RequiresOptIn
annotation class FirstMarker

@kotlin.RequiresOptIn
annotation class SecondMarker

@OptIn(FirstMarker::class, SecondMarker::class)
fun useOptIn(): Int = 1
