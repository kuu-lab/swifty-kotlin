package kuu1730eofcontracts

import kotlinx.io.EOFException
import kotlinx.io.IOException

// Native adds EOFException(message, cause) beyond the common expect surface.
// Java's EOFException alias has no such constructor; this is a Native check.
private class ChildEOF(message: String?, cause: Throwable?) : EOFException(message, cause)

private fun observe(label: String, exception: EOFException, message: String?, cause: Throwable?) {
    check(exception.message == message)
    check(exception.cause === cause)
    var caughtSame = false
    try {
        throw exception
    } catch (caught: IOException) {
        caughtSame = caught === exception
        check(caught.cause === cause)
    }
    check(caughtSame)
    println("$label:${exception.message == message}:${exception.cause === cause}:$caughtSame")
}

public fun runEofContract() {
    val root = IOException("owned-root")
    observe("noarg", EOFException(), null, null)
    observe("legacy", EOFException("legacy"), "legacy", null)
    observe("both", EOFException(message = "explicit", cause = root), "explicit", root)
    observe("null-message", EOFException(null, root), null, root)
    observe("null-cause", EOFException("explicit", null), "explicit", null)
    observe("both-null", EOFException(null, null), null, null)
    observe("child", ChildEOF("derived", root), "derived", root)
    observe("reused-root", EOFException("again", root), "again", root)
    check(root.message == "owned-root" && root.cause == null)
    println("done")
}
