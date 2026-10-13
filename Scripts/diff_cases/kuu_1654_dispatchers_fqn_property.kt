import kotlinx.coroutines.Dispatchers as ShortDispatchers

fun main() {
    val dispatchers = ShortDispatchers
    println(kotlinx.coroutines.Dispatchers.Default === ShortDispatchers.Default)
    println(kotlinx.coroutines.Dispatchers.Default === dispatchers.Default)
}
