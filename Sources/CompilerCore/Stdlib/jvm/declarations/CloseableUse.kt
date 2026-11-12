package kotlin.io

import java.io.Closeable

@PublishedApi
internal fun Closeable?.closeFinally(cause: Throwable?) {}

public inline fun <T : Closeable?, R> T.use(block: (T) -> R): R {
    val resource = this
    val closeable: Closeable? = resource
    var failure: Throwable? = null
    try {
        return block(resource)
    } catch (error: Throwable) {
        failure = error
        throw error
    } finally {
        closeable.closeFinally(failure)
    }
}
