import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testCoroutineContextEmptyIdentity(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlin.coroutines.*

            class MyKey(val v: String) : AbstractCoroutineContextElement(Key) {
                companion object Key : CoroutineContext.Key<MyKey>
            }
            class DirectElement : CoroutineContext.Element {
                companion object Key : CoroutineContext.Key<DirectElement>
                override val key: CoroutineContext.Key<*> get() = Key
            }
            object SingletonElement : CoroutineContext.Element {
                object Key : CoroutineContext.Key<SingletonElement>
                override val key: CoroutineContext.Key<*> = Key
            }

            fun checkIdentity(context: CoroutineContext) {
                val empty: CoroutineContext = EmptyCoroutineContext
                println((context + empty) === context)
                println(context.plus(empty) === context)
                println((empty + context) === context)
                println(empty.plus(context) === context)
            }

            fun main() {
                println(EmptyCoroutineContext.get(MyKey))
                println(EmptyCoroutineContext[MyKey])
                val ctx = EmptyCoroutineContext + MyKey("hello")
                println(ctx.get(MyKey)?.v)
                println(ctx[MyKey]?.v)
                println(ctx.minusKey(MyKey)[MyKey])
                println(ctx.fold("") { acc, _ -> acc })

                val preserved: CoroutineContext = ctx + EmptyCoroutineContext
                println(preserved.get(MyKey)?.v)
                println(preserved[MyKey]?.v)
                println(preserved.fold("") { acc, element -> acc + (element as MyKey).v })
                println(preserved.minusKey(MyKey)[MyKey])
                println(preserved.minusKey(DirectElement.Key) === ctx)

                checkIdentity(ctx)
                checkIdentity(DirectElement())
                checkIdentity(SingletonElement)
                checkIdentity(EmptyCoroutineContext)
            }
            """,
            expectedOutput: "null\nnull\nhello\nhello\nnull\n\nhello\nhello\nhello\nnull\ntrue\n"
                + String(repeating: "true\n", count: 16),
            moduleName: "KUU1123CoroutineContextEmptyIdentity",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
