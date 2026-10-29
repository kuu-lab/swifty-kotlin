@testable import CompilerCore
import Foundation
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

/// `kswiftc --run` interpreter: supported programs must produce the exact
/// output the native path prints, and anything outside the modelled subset must
/// be reported as an explicit fallback (never silently mis-executed).
@Suite
struct KIRInterpreterTests {
    private func interpret(_ source: String, artifact: Bool = true) throws -> KIRInterpreterOutcome {
        if artifact { TestStdlibCache.shared.prepare() }
        let ctx = makeContextFromSource(source, emit: .executable, allowDefaultStdlibLibrary: artifact)
        try runToLowering(ctx)
        #expect(!ctx.diagnostics.hasError)
        return KIRInterpreter.run(context: ctx)
    }

    @Test
    func executesHelloWorld() throws {
        let outcome = try interpret("""
        fun main() {
            println("hello")
        }
        """)
        #expect(outcome == .completed(stdout: "hello\n"))
    }

    @Test
    func executesRecursionLoopsAndTemplates() throws {
        let outcome = try interpret("""
        fun fib(n: Int): Int = if (n < 2) n else fib(n - 1) + fib(n - 2)
        fun main() {
            var s = 0
            for (i in 1..5) { s += i }
            println("sum=$s fib=${fib(10)} ok=${s > 10}")
            var n = 3
            while (n > 0) { print(n); n -= 1 }
            println()
        }
        """)
        #expect(outcome == .completed(stdout: "sum=15 fib=55 ok=true\n321\n"))
    }

    @Test
    func int32ArithmeticWrapsLikeNative() throws {
        let outcome = try interpret("""
        fun main() {
            val big = 2147483647
            println(big + 1)
            println(7 / 2)
            println(-7 % 3)
            println((6 and 3) or 8)
        }
        """)
        #expect(outcome == .completed(stdout: "-2147483648\n3\n-1\n10\n"))
    }

    @Test
    func topLevelStateIsInterpreted() throws {
        let outcome = try interpret("""
        var counter = 0
        fun bump(): Int { counter += 1; return counter }
        fun main() {
            bump(); bump()
            println("counter=${bump()}")
        }
        """)
        #expect(outcome == .completed(stdout: "counter=3\n"))
    }

    /// KUU-3687: `IValue.null` must be distinct from every `.int` payload.
    /// A real `Long.MIN_VALUE` shares the native null-sentinel bit pattern, so
    /// a sentinel-based model printed it as "null"; a dedicated `.null` case
    /// keeps value and null separate across printing, concat, calls and
    /// nullable equality.
    @Test
    func longMinValueStaysDistinctFromNull() throws {
        let outcome = try interpret("""
        fun f(x: Long): Long = x
        fun main() {
            val m = -9223372036854775807L - 1L
            println(m)
            println(f(m))
            println("v=" + f(m))
            println("w=$m")
            val nl: Long? = m
            println(nl)
            println("n=$nl")
            val z: Long? = null
            println(z)
            println("z=$z")
            if (nl == null) println("nl null") else println("nl not null")
            if (z == null) println("z null") else println("z not null")
            println(nl == m)
            println(nl != null)
        }
        """)
        #expect(outcome == .completed(stdout: """
        -9223372036854775808
        -9223372036854775808
        v=-9223372036854775808
        w=-9223372036854775808
        -9223372036854775808
        n=-9223372036854775808
        null
        z=null
        nl not null
        z null
        true
        true

        """))
    }

    @Test
    func collectionsFallBackToNativeExecution() throws {
        let outcome = try interpret("""
        fun main() {
            println(listOf(3, 1, 2).sorted())
        }
        """)
        guard case let .fallback(reason) = outcome else {
            Issue.record("expected fallback, got \(outcome)")
            return
        }
        #expect(reason.contains("main"))
    }

    @Test
    func divisionByZeroBailsOutWithoutEmittingOutput() throws {
        let outcome = try interpret("""
        fun main() {
            println("before")
            val zero = 0
            println(1 / zero)
        }
        """)
        // The buffered "before" must not leak: native re-runs from scratch.
        #expect(outcome == .fallback(reason: "division by zero"))
    }

    @Test
    func unboundedRecursionFallsBackInsteadOfCrashing() throws {
        let outcome = try interpret("""
        fun down(n: Int): Int = if (n == 0) 0 else 1 + down(n - 1)
        fun main() {
            println(down(100000))
        }
        """)
        #expect(outcome == .fallback(reason: "call depth exceeded"))
    }

    @Test
    func executesAgainstSourceInjectedStdlibToo() throws {
        let outcome = try interpret("""
        fun main() {
            println("from source stdlib")
        }
        """, artifact: false)
        // Source-injected stdlib initialisers are real KIR bodies; whether they
        // are all modelled or not, the result must be well-formed, never a crash.
        switch outcome {
        case let .completed(stdout): #expect(stdout == "from source stdlib\n")
        case let .fallback(reason): #expect(!reason.isEmpty)
        }
    }
}
