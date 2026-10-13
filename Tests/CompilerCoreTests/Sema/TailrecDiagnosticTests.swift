#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct TailrecDiagnosticTests {
    struct Case: Sendable {
        let name: String
        let source: String
        let expectsWarning: Bool
    }

    static let cases: [Case] = [
        Case(name: "changedReceiver", source: """
        tailrec fun Long.gcd(other: Long): Long =
            if (other == 0L) this
            else other.gcd(this % other)

        fun main() {}
        """, expectsWarning: false),
        Case(name: "thisReceiver", source: """
        tailrec fun Long.count(other: Long): Long =
            if (other == 0L) this else this.count(other - 1L)
        fun main() {}
        """, expectsWarning: false),
        Case(name: "implicitReceiver", source: """
        tailrec fun Long.count(other: Long): Long =
            if (other == 0L) this else count(other - 1L)
        fun main() {}
        """, expectsWarning: false),
        Case(name: "changedReceiverBlock", source: """
        tailrec fun Long.gcd(other: Long): Long {
            if (other == 0L) return this
            return other.gcd(this % other)
        }
        fun main() {}
        """, expectsWarning: false),
        Case(name: "differentReceiverOverload", source: """
        fun Int.gcd(other: Long): Long = other
        tailrec fun Long.gcd(other: Long): Long =
            if (other == 0L) this else 1.gcd(other)
        fun main() {}
        """, expectsWarning: true),
        Case(name: "thisReceiverDifferentCallee", source: """
        fun Long.gcd(other: Int): Long = this
        tailrec fun Long.gcd(other: Long): Long =
            if (other == 0L) this else this.gcd(1)
        fun main() {}
        """, expectsWarning: true),
        Case(name: "directDifferentCallee", source: """
        fun count(other: Int): Long = 0L
        tailrec fun count(other: Long): Long =
            if (other == 0L) 0L else count(1)
        fun main() {}
        """, expectsWarning: true),
        Case(name: "changedReceiverNonTail", source: """
        tailrec fun Long.gcd(other: Long): Long =
            if (other == 0L) this else 1L + other.gcd(this % other)
        fun main() {}
        """, expectsWarning: true),
        Case(name: "thisReceiverNonTail", source: """
        tailrec fun Long.count(other: Long): Long =
            if (other == 0L) this else 1L + this.count(other - 1L)
        fun main() {}
        """, expectsWarning: true),
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
            #expect(warnings.count == (testCase.expectsWarning ? 1 : 0))
        }
    }
}
#endif
