package golden.sema

// KSP-721: generic upper bound <T : AutoCloseable> should allow .use {}
// AutoCloseable is a source-backed interface and Closeable extends it, so the
// constraint solver treats AutoCloseable receivers as closeable.

class MyAutoResource : AutoCloseable {
    override fun close() {}
}

fun <T : AutoCloseable> useIt(t: T): Unit {
    t.use { }
}

fun callSite(): Unit {
    useIt(MyAutoResource())
}
