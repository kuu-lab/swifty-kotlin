@file:OptIn(
    kotlinx.coroutines.ExperimentalCoroutinesApi::class,
    kotlinx.coroutines.DelicateCoroutinesApi::class,
    kotlinx.coroutines.InternalCoroutinesApi::class
)

import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlinx.coroutines.CopyableThreadContextElement
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.ThreadContextElement
import kotlinx.coroutines.handleCoroutineException

private class StringThreadContextElement : ThreadContextElement<String> {
    override val key: CoroutineContext.Key<*> get() = Key

    override fun updateThreadContext(context: CoroutineContext): String = "previous"

    override fun restoreThreadContext(context: CoroutineContext, oldState: String) {}

    private companion object Key : CoroutineContext.Key<StringThreadContextElement>
}

private class CopyableStringThreadContextElement : CopyableThreadContextElement<String> {
    override val key: CoroutineContext.Key<*> get() = Key

    override fun updateThreadContext(context: CoroutineContext): String = "copyable"

    override fun restoreThreadContext(context: CoroutineContext, oldState: String) {}

    override fun copyForChild(): CopyableThreadContextElement<String> = this

    override fun mergeForChild(overwritingElement: CoroutineContext.Element): CoroutineContext =
        overwritingElement

    private companion object Key : CoroutineContext.Key<CopyableStringThreadContextElement>
}

fun main() {
    val threadElement: ThreadContextElement<String> = StringThreadContextElement()
    println(threadElement.updateThreadContext(EmptyCoroutineContext))
    threadElement.restoreThreadContext(EmptyCoroutineContext, "restored")

    val copyable: CopyableThreadContextElement<String> = CopyableStringThreadContextElement()
    println(copyable.copyForChild() === copyable)
    println(copyable.mergeForChild(threadElement) === threadElement)

    var factoryResult = ""
    val factoryHandler = CoroutineExceptionHandler { _, exception ->
        factoryResult = exception.message ?: "missing"
    }
    val factoryContext = EmptyCoroutineContext + factoryHandler
    println(factoryContext[CoroutineExceptionHandler] === factoryHandler)
    factoryHandler.handleException(factoryContext, IllegalStateException("direct"))
    println(factoryResult)
    handleCoroutineException(factoryContext, IllegalStateException("routed"))
    println(factoryResult)
}
