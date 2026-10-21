import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testKUU2127InlineLambdaBreakContinue(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            inline fun invokeBlock(block: () -> Unit) { block() }

            fun breakFromInline(): Int {
                var count = 0
                outer@ while (count < 1) {
                    invokeBlock { count += 1; break@outer }
                    count += 100
                }
                return count
            }

            fun continueFromNestedInline(): Int {
                var count = 0
                outer@ while (count < 3) {
                    invokeBlock { invokeBlock { count += 1; continue@outer } }
                    count += 100
                }
                return count
            }

            fun continueThroughFinally(): Int {
                var iteration = 0
                var count = 0
                outer@ while (iteration < 2) {
                    invokeBlock {
                        try {
                            iteration += 1
                            count += 1
                            continue@outer
                        } finally {
                            count += 100
                        }
                    }
                    count += 1000
                }
                return count
            }

            fun breakThroughFinally(): Int {
                var count = 0
                outer@ while (count < 1) {
                    invokeBlock {
                        try {
                            count += 1
                            break@outer
                        } finally {
                            count += 100
                        }
                    }
                    count += 1000
                }
                return count
            }

            fun nestedFinally(): Int {
                var count = 0
                outer@ for (outerIteration in 0..1) {
                    invokeBlock {
                        try {
                            count += 1
                            for (innerIteration in 0..1) {
                                invokeBlock {
                                    try {
                                        count += 10
                                        continue
                                    } finally {
                                        count += 1000
                                    }
                                }
                            }
                            continue@outer
                        } finally {
                            count += 10000
                        }
                    }
                }
                return count
            }

            fun main() {
                println(breakFromInline())
                println(continueFromNestedInline())
                println(continueThroughFinally())
                println(breakThroughFinally())
                println(nestedFinally())
            }
            """,
            expectedOutput: "1\n3\n202\n101\n24042\n",
            moduleName: "KUU2127InlineLambdaBreakContinue",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    /// The inline callee's own labels (`run2` below defines low-numbered ones)
    /// must not capture the lambda's break/continue targets in the caller.
    @Test(arguments: [true, false])
    func testKUU2732InlineLambdaBreakContinueWithCalleeLabels(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            inline fun run2(block: () -> Unit) = block()

            fun main() {
                for (i in 1..3) { run2 { if (i == 2) break } }
                println("done")
                var s = 0
                for (i in 1..3) { run2 { if (i == 2) continue }; s += i }
                println(s)
                outer@ for (i in 1..3) {
                    for (j in 1..3) { run2 { if (j == 2) break@outer } }
                    println("unreachable")
                }
                println("end")
            }
            """,
            expectedOutput: "done\n4\nend\n",
            moduleName: "KUU2732InlineLambdaBreakContinue",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func testKUU2757NestedInlineContinueTracksRelocatedLoopLabel(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            inline fun invokeBlock(block: () -> Unit) { block() }

            fun f1(): Int {
                var count = 0
                for (o in 0..1) {
                    invokeBlock {
                        for (i in 0..1) {
                            invokeBlock { count += 10; continue }
                        }
                    }
                }
                return count
            }

            fun main() { println(f1()) }
            """,
            expectedOutput: "40\n",
            moduleName: "KUU2757NestedInlineContinueLabelRemap",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
