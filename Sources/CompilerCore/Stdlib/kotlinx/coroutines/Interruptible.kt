package kotlinx.coroutines

import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext

@Suppress("UNCHECKED_CAST")
public suspend fun <T> runInterruptible(
    context: CoroutineContext = EmptyCoroutineContext,
    block: () -> T
): T {
    val result: Any = withContext(context) { block() as Any }
    return result as T
}
