#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct TailrecDiagnosticTests {
    struct Case: Sendable {
        let name: String
        let source: String
        let expectedWarningCount: Int
    }

    static let cases: [Case] = [
        Case(name: "changedReceiver", source: """
        tailrec fun Long.gcd(other: Long): Long =
            if (other == 0L) this
            else other.gcd(this % other)

        fun main() {}
        """, expectedWarningCount: 0),
        Case(name: "thisReceiver", source: """
        tailrec fun Long.count(other: Long): Long =
            if (other == 0L) this else this.count(other - 1L)
        fun main() {}
        """, expectedWarningCount: 0),
        Case(name: "implicitReceiver", source: """
        tailrec fun Long.count(other: Long): Long =
            if (other == 0L) this else count(other - 1L)
        fun main() {}
        """, expectedWarningCount: 0),
        Case(name: "changedReceiverBlock", source: """
        tailrec fun Long.gcd(other: Long): Long {
            if (other == 0L) return this
            return other.gcd(this % other)
        }
        fun main() {}
        """, expectedWarningCount: 0),
        Case(name: "returnInCondition", source: """
        tailrec fun count(n: Int): Int {
            while (if (n > 0) return count(n - 1) else false) {}
            return 0
        }
        fun main() {}
        """, expectedWarningCount: 0),
        Case(name: "returnInInitializer", source: """
        tailrec fun count(n: Int): Int {
            val value = if (n > 0) return count(n - 1) else 0
            return value
        }
        fun main() {}
        """, expectedWarningCount: 0),
        Case(name: "returnInArgument", source: """
        fun accept(value: Int): Int = value
        tailrec fun count(n: Int): Int {
            accept(if (n > 0) return count(n - 1) else 0)
            return 0
        }
        fun main() {}
        """, expectedWarningCount: 0),
        Case(name: "returnInLambdaIsNotFunctionTailCall", source: """
        tailrec fun count(n: Int): Int {
            val call: () -> Int = { if (n == 0) 0 else count(n - 1) }
            return call() + 1
        }
        fun main() {}
        """, expectedWarningCount: 1),
        Case(name: "returnInTryIsNotTailCall", source: """
        tailrec fun count(n: Int): Int {
            if (n == 0) return 0
            try { return count(n - 1) } finally {}
        }
        fun main() {}
        """, expectedWarningCount: 1),
        Case(name: "differentReceiverOverload", source: """
        fun Int.gcd(other: Long): Long = other
        tailrec fun Long.gcd(other: Long): Long =
            if (other == 0L) this else 1.gcd(other)
        fun main() {}
        """, expectedWarningCount: 1),
        Case(name: "thisReceiverDifferentCallee", source: """
        fun Long.gcd(other: Int): Long = this
        tailrec fun Long.gcd(other: Long): Long =
            if (other == 0L) this else this.gcd(1)
        fun main() {}
        """, expectedWarningCount: 1),
        Case(name: "directDifferentCallee", source: """
        fun count(other: Int): Long = 0L
        tailrec fun count(other: Long): Long =
            if (other == 0L) 0L else count(1)
        fun main() {}
        """, expectedWarningCount: 1),
        Case(name: "changedReceiverNonTail", source: """
        tailrec fun Long.gcd(other: Long): Long =
            if (other == 0L) this else 1L + other.gcd(this % other)
        fun main() {}
        """, expectedWarningCount: 1),
        Case(name: "thisReceiverNonTail", source: """
        tailrec fun Long.count(other: Long): Long =
            if (other == 0L) this else 1L + this.count(other - 1L)
        fun main() {}
        """, expectedWarningCount: 1),
    ]

    @Test(arguments: cases)
    func diagnosesResolvedTailCalls(testCase: Case) throws {
        try withTemporaryFile(contents: testCase.source) { path in
            let ctx = makeCompilationContext(
                inputs: [path], moduleName: testCase.name, includeStdlib: false
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError)
            let warnings = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-SEMA-TAILREC" && $0.severity == .warning
            }
            #expect(warnings.count == testCase.expectedWarningCount)
        }
    }
}
#endif
