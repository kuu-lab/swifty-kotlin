import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true])
    func testGenericCallbackOverridesDispatchThroughInterfaces(artifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.runBlocking

            interface Callbacks<T> {
                fun visit(action: (T) -> Unit)
                fun nested(action: (List<T>) -> Unit)
                fun produce(action: () -> T): T
                fun receiver(action: T.() -> Unit)
                suspend fun suspended(action: suspend (T) -> Unit)
            }

            class IntCallbacks : Callbacks<Int> {
                override fun visit(action: (Int) -> Unit) { action(1) }
                override fun nested(action: (List<Int>) -> Unit) { action(listOf(2, 3)) }
                override fun produce(action: () -> Int): Int = action()
                override fun receiver(action: Int.() -> Unit) { 5.action() }
                override suspend fun suspended(action: suspend (Int) -> Unit) { action(6) }
            }

            interface ConcreteCallbacks {
                fun describe(action: (Int) -> String): String = action(7)
            }

            interface StringCallbacks : ConcreteCallbacks {
                fun describe(action: (String, String) -> String): String
            }

            class StringImpl : StringCallbacks {
                override fun describe(action: (String, String) -> String): String = action("text", "!")
            }

            fun main() = runBlocking {
                val callbacks: Callbacks<Int> = IntCallbacks()
                callbacks.visit { println(it) }
                callbacks.nested { println(it) }
                println(callbacks.produce { 4 })
                callbacks.receiver { println(this) }
                callbacks.suspended { println(it) }
                val concrete: ConcreteCallbacks = StringImpl()
                println(concrete.describe { "base=$it" })
                val strings: StringCallbacks = StringImpl()
                println(strings.describe { a, b -> a + b })
            }
            """,
            expectedOutput: "1\n[2, 3]\n4\n5\n6\nbase=7\ntext!\n",
            allowDefaultStdlibLibrary: artifact
        )
    }

    @Test(arguments: [false, true])
    func testSharedFlowCollectThroughErasedFlow(artifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.runBlocking
            import kotlinx.coroutines.flow.*

            class ProbeShared : SharedFlow<Int> {
                override val replayCache: List<Int> get() = listOf(4)
                override suspend fun collect(collector: suspend (Int) -> Unit) {
                    collector(4)
                }
            }

            fun main() = runBlocking {
                val erased: Flow<Int> = ProbeShared()
                erased.collect { println(it) }
                erased.collect { println(it) }
                val shared = MutableSharedFlow<Int>(2)
                shared.tryEmit(1)
                val subscribed: Flow<Int> = shared.onSubscription { emit(0) }
                subscribed.collect { println(it) }
                subscribed.collect { println(it) }
            }
            """,
            expectedOutput: "4\n4\n0\n1\n0\n1\n",
            allowDefaultStdlibLibrary: artifact
        )
    }
}
