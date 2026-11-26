#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct SafeCallArgumentDefiniteAssignmentTests {
    @Test
    func testAssignmentInsideSafeCallArgumentIsNotDefinite() throws {
        let sources = [
            """
            package blockArgument
            fun read(s: String?): Int {
                var x: Int
                s?.let(if (true) { x = 5; { _: String -> } } else { { _ -> } })
                return x
            }
            """,
            """
            package nestedContract
            fun read(s: String?): Int {
                var x: Int
                s?.takeIf(run { x = 5; { it.isEmpty() } })
                return x
            }
            """,
            """
            package definitelyNullReceiver
            fun read(): Int {
                var x: Int
                val s: String? = null
                s?.let(if (true) { x = 5; { _: String -> } } else { { _ -> } })
                return x
            }
            """,
        ]
        for source in sources {
            _ = try semaContext(from: [source], expecting: [.error("KSWIFTK-SEMA-0031")])
        }
    }

    @Test
    func testAssignmentInsideSafeCallReceiverStaysDefinite() throws {
        let sources = [
            """
            package receiverAssignment
            fun read(s: String?): Int {
                var x: Int
                run { x = 5; s }?.let { _ -> }
                return x
            }
            """,
            """
            package plainCallArgument
            fun read(s: String): Int {
                var x: Int
                s.plus(run { x = 5; "a" })
                return x
            }
            """,
        ]
        for source in sources {
            _ = try semaContext(from: [source])
        }
    }

    @Test
    func testElvisNothingFallbackKeepsArgumentAssignmentDefinite() throws {
        let sources = [
            """
            package elvisReturn
            fun read(s: String?): Int {
                var x: Int
                s?.plus(run { x = 5; "a" }) ?: return 0
                return x
            }
            """,
        ]
        for source in sources {
            _ = try semaContext(from: [source])
        }
    }

    @Test
    func testValAssignedInSafeCallArgumentRejectsLaterReassignment() throws {
        let sources = [
            """
            package valReassign
            fun read(s: String?, b: Boolean): Int {
                val x: Int
                s?.plus(if (b) { x = 5; "a" } else { x = 6; "b" })
                x = 7
                return x
            }
            """,
        ]
        for source in sources {
            _ = try semaContext(from: [source], expecting: [.error("KSWIFTK-SEMA-0014")])
        }
    }

    @Test
    func testElvisNothingFallbackAfterSafeCallChainKeepsEarlierArgumentAssignmentDefinite() throws {
        let sources = [
            """
            package elvisChain
            fun read(s: String?): Int {
                var x: Int
                s?.plus(run { x = 5; "a" })?.length ?: return 0
                return x
            }
            """,
        ]
        for source in sources {
            _ = try semaContext(from: [source])
        }
    }

    @Test
    func testPossibleAssignmentSurvivesBlockAndBranchJoin() throws {
        let sources = [
            """
            package branchJoin
            fun read(s: String?, b: Boolean, c: Boolean): Int {
                val x: Int
                if (b) {
                    s?.plus(if (c) { x = 5; "a" } else { x = 6; "b" })
                } else {
                    x = 7
                }
                x = 8
                return x
            }
            """,
        ]
        for source in sources {
            _ = try semaContext(from: [source], expecting: [.error("KSWIFTK-SEMA-0014")])
        }
    }

    @Test
    func testPossibleAssignmentFromBranchThatNeverCompletesIsDropped() throws {
        let sources = [
            """
            package nonCompletingBranch
            fun read(s: String?, b: Boolean, c: Boolean): Int {
                val x: Int
                if (b) {
                    s?.plus(if (c) { x = 5; "a" } else { x = 6; "b" })
                    try { println("work") } finally { return 0 }
                }
                x = 8
                return x
            }
            """,
        ]
        for source in sources {
            _ = try semaContext(from: [source])
        }
    }

    @Test
    func testPossibleAssignmentSurvivesBranchWithLabeledReturnToInlineLambda() throws {
        let sources = [
            """
            package labeledReturnBranch
            fun read(s: String?, b: Boolean, c: Boolean, d: Boolean): Int {
                val x: Int
                if (b) {
                    s?.plus(if (c) { x = 5; "a" } else { x = 6; "b" })
                    run<Int> {
                        if (d) return@run 1
                        throw IllegalStateException()
                    }
                }
                x = 8
                return x
            }
            """,
        ]
        for source in sources {
            _ = try semaContext(from: [source], expecting: [.error("KSWIFTK-SEMA-0014")])
        }
    }

    @Test
    func testPossibleAssignmentIsDroppedWhenFinallyAlwaysExitsAfterLambdaReturn() throws {
        let sources = [
            """
            package lambdaReturnThenFinallyExit
            fun read(s: String?, b: Boolean, c: Boolean, d: Boolean): Int {
                val x: Int
                if (b) {
                    s?.plus(if (c) { x = 5; "a" } else { x = 6; "b" })
                    try {
                        run<Int> {
                            if (d) return@run 1
                            throw IllegalStateException()
                        }
                    } finally {
                        return 0
                    }
                }
                x = 8
                return x
            }
            """,
        ]
        for source in sources {
            _ = try semaContext(from: [source])
        }
    }
}
#endif
