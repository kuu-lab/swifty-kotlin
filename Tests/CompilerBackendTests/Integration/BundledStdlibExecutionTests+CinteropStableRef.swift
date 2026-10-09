import Testing

extension BundledStdlibExecutionTests {
    // KSP-1217: kotlinx.cinterop.StableRef was previously a nominal-only
    // synthetic stub with no create/get/dispose/asCPointer wiring, so
    // kotlin.native.concurrent.callContinuation0/1/2 (which upstream
    // implements purely in terms of StableRef) could never resolve past
    // Sema. Both are now bundled Kotlin source backed by kk_stable_ref_create/
    // _deref/_dispose (Sources/Runtime/RuntimeNativeAPI.swift).

    @Test
    func testStableRefRoundTripsThroughCOpaquePointer() throws {
        try compileAndRunKotlin(
            """
            @file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
            import kotlinx.cinterop.COpaquePointer
            import kotlinx.cinterop.StableRef
            import kotlinx.cinterop.asStableRef

            fun main() {
                val ref = StableRef.create("hello")
                val pointer: COpaquePointer = ref.asCPointer()
                val recovered = pointer.asStableRef<String>()
                println(recovered.get())
                ref.dispose()
            }
            """,
            expectedOutput: "hello\n"
        )
    }

    /// The same target object may be wrapped by several independent StableRef
    /// handles at once — disposing one must not unpin a sibling handle to the
    /// same object. This is why `kk_stable_ref_create`/`_dispose` keep their
    /// own per-target refcount (`stableRefCounts`) rather than reusing
    /// `Pinned<T>`'s `pinnedObjectCounts`, whose counts are driven by
    /// per-handle `RuntimePinnedBox` unpins.
    @Test
    func testIndependentStableRefsToSameObjectSurviveSiblingDispose() throws {
        try compileAndRunKotlin(
            """
            @file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
            import kotlinx.cinterop.StableRef

            fun main() {
                val shared = "shared-target"
                val refA = StableRef.create(shared)
                val refB = StableRef.create(shared)
                refA.dispose()
                println(refB.get())
                refB.dispose()
            }
            """,
            expectedOutput: "shared-target\n"
        )
    }

    // callContinuation0/1/2 のプリミティブ型引数はここで、参照型と混在型の
    // 引数は次の KUU-548 回帰テストで実行検証する。
    @Test
    func testCallContinuationFunctionsInvokeWrappedClosures() throws {
        try compileAndRunKotlin(
            """
            @file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
            @file:Suppress("DEPRECATION")
            import kotlinx.cinterop.StableRef
            import kotlin.native.concurrent.callContinuation0
            import kotlin.native.concurrent.callContinuation1
            import kotlin.native.concurrent.callContinuation2

            fun main() {
                val block0: () -> Unit = { print("c0;") }
                val ref0 = StableRef.create(block0)
                ref0.asCPointer().callContinuation0()
                ref0.dispose()

                val block1: (Int) -> Unit = { p1 -> print("c1($p1);") }
                val pair = Pair(StableRef.create(block1), 42)
                val refPair = StableRef.create(pair)
                refPair.asCPointer().callContinuation1<Int>()
                pair.first.dispose()
                refPair.dispose()

                val block2: (Int, Int) -> Unit = { p1, p2 -> print("c2($p1,$p2);") }
                val triple = Triple(StableRef.create(block2), 7, 9)
                val refTriple = StableRef.create(triple)
                refTriple.asCPointer().callContinuation2<Int, Int>()
                triple.first.dispose()
                refTriple.dispose()
                println()
            }
            """,
            expectedOutput: "c0;c1(42);c2(7,9);\n"
        )
    }

    // KUU-548 (#6866) でフィールド経由のジェネリック関数値呼び出しが修正された。
    // 参照型（String）と混在型（Int/String）の StableRef/closure 動作を実行時に固定する。
    @Test
    func testCallContinuationFunctionsInvokeWrappedClosuresWithReferenceTypeArguments() throws {
        try compileAndRunKotlin(
            """
            @file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
            @file:Suppress("DEPRECATION")
            import kotlinx.cinterop.StableRef
            import kotlin.native.concurrent.callContinuation1
            import kotlin.native.concurrent.callContinuation2

            fun main() {
                val block1: (String) -> Unit = { p1 -> print("c1($p1);") }
                val pair = Pair(StableRef.create(block1), "hello")
                val refPair = StableRef.create(pair)
                refPair.asCPointer().callContinuation1<String>()
                pair.first.dispose()
                refPair.dispose()

                val block2: (Int, String) -> Unit = { p1, p2 -> print("c2($p1,$p2);") }
                val triple = Triple(StableRef.create(block2), 7, "x")
                val refTriple = StableRef.create(triple)
                refTriple.asCPointer().callContinuation2<Int, String>()
                triple.first.dispose()
                refTriple.dispose()
                println()
            }
            """,
            expectedOutput: "c1(hello);c2(7,x);\n"
        )
    }
}
