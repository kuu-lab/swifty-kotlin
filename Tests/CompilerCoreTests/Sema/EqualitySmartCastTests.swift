#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct EqualitySmartCastTests {
    private func expectClean(_ source: String, _ comment: String = "") throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(comment) got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func identityEqualityNarrowsWiderOperandInTrueBranch() throws {
        try expectClean("""
        open class Node {
            fun markPrev(prev: Any): Node {
                if (prev === this) return prev
                return Node()
            }
        }
        """)
    }

    @Test
    func identityInequalityNarrowsOnElsePath() throws {
        try expectClean("""
        open class Node {
            fun markPrev(prev: Any): Node {
                if (prev !== this) return Node()
                return prev
            }
        }
        """)
    }

    @Test
    func structuralEqualityNarrowsWiderOperand() throws {
        try expectClean("""
        open class Node
        fun markPrev(prev: Any, other: Node): Node {
            if (prev == other) return prev
            return other
        }
        """)
    }

    @Test
    func unrelatedSidesDoNotNarrow() throws {
        let source = """
        open class Node
        open class Other
        fun probe(prev: Any, other: Other): Node {
            if (prev === other) return prev
            return Node()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(
                ctx.diagnostics.hasError,
                "`prev === other` must not narrow `prev` to Node"
            )
        }
    }

    @Test
    func branchNarrowingJoinsIntoPostIfFlowState() throws {
        // From ktor LockFreeLinkedList.markPrev: the true branch narrows `prev`
        // via `===` and the else branch via `as`; both leave `prev` at Node, so
        // the merge keeps it and `return prev` compiles.
        try expectClean("""
        class Atomic<T>(var v: T) {
            inline fun loop(action: (T) -> Unit) { action(v) }
            fun cas(a: T, b: T): Boolean = true
        }
        open class Node {
            val _prev = Atomic<Any>(this)
            fun removed(): Int = 1
            private fun findHead(): Node = this
            fun markPrev(): Node {
                _prev.loop { prev ->
                    val removedPrev = (if (prev === this) findHead() else (prev as Node)).removed()
                    if (_prev.cas(prev, removedPrev)) return prev
                }
                return this
            }
        }
        """)
    }

    @Test
    func oneSidedNarrowingDoesNotSurviveJoin() throws {
        // `prev` narrows to Node only on the true branch; after the if it is
        // still Any, so `return prev` must fail.
        let source = """
        open class Node {
            fun markPrev(prev: Any): Node {
                val x = if (prev === this) 1 else 2
                return prev
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError, "one-sided narrowing must not leak past the join")
        }
    }
}
#endif
