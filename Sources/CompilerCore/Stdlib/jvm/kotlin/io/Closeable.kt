package kotlin.io

import java.io.Closeable
import kotlin.jvm.internal.__jvmCloseResource

@PublishedApi
internal fun Closeable?.closeFinally(cause: Throwable?) {
    if (this == null) return
    if (cause == null) {
        __jvmCloseResource(this)
    } else {
        try {
            __jvmCloseResource(this)
        } catch (closeFailure: Throwable) {
            if (cause !== closeFailure) cause.addSuppressed(closeFailure)
        }
    }
}
