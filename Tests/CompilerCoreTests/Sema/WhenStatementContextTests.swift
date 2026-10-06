#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct WhenStatementContextTests {
    @Test func testCallAndIndexSubjectsInStatementPosition() throws {
        let source = """
        const val SUCCESS: Int = 1
        const val FAILURE: Int = 2
        class N { fun tryIt(): Int = SUCCESS }
        fun methodSubject(n: N) {
            while (true) {
                when (n.tryIt()) {
                    SUCCESS -> return
                    FAILURE -> return
                }
            }
        }
        fun number(): Int = 1
        fun callSubject() { when (number()) { 1 -> println(1) } }
        fun stringIndexSubject(query: String, index: Int) {
            when (query[index]) { '&' -> println(index) }
        }
        fun stringIndexInLoop(query: String) {
            for (index in 0 until query.length) {
                when (query[index]) { '&' -> continue }
                println(index)
            }
        }
        fun arrayIndexSubject(values: IntArray, index: Int) {
            when (values[index]) { 1 -> println(index) }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testIssueReproductionAndLoopBodies() throws {
        let source = """
        private const val LF: Byte = 10
        fun byteSubjectWhen(b: Byte): Int {
            when (b) { LF -> return 1 }
            return 0
        }
        fun encodeToImpl(fromIndex: Int, toIndex: Int): Int {
            var start = fromIndex
            if (start >= toIndex) return 0
            while (true) {
                start += 1
                when { start >= toIndex -> break }
            }
            return start
        }
        fun doWhileBody(limit: Int): Int {
            var n = 0
            do {
                n += 1
                when { n >= limit -> break }
            } while (n < limit)
            return n
        }
        fun forBody(): Int {
            var sum = 0
            for (n in 1..3) {
                sum += n
                when (n) { 2 -> continue }
            }
            return sum
        }
        fun bareWhileBody(flag: Boolean) {
            while (flag) when { flag -> break }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        let sourceDiagnostics = diagnosticsForPath(ctx.options.inputs[0], in: ctx)
        #expect(!sourceDiagnostics.contains { $0.code == "KSWIFTK-SEMA-0096" }, "Got: \(sourceDiagnostics)")
    }

    @Test func testDiscardedControlFlowBranchesAndUnitLambdaBodies() throws {
        let source = """
        fun runAction(action: () -> Unit) { action() }
        fun statements(flag: Boolean, n: Int) {
            if (flag) { when { n > 0 -> println(n) } }
            if (flag) {
                when (n) { 1 -> println(n) }
            } else {
                when { n > 0 -> println(n) }
            }
            when (n) {
                1 -> { when { flag -> println(n) } }
                else -> { when (n) { 2 -> println(n) } }
            }
            when {
                flag -> { when (n) { 1 -> println(n) } }
                else -> { when { n > 0 -> println(n) } }
            }
            try {
                when { flag -> println(n) }
            } catch (e: Exception) {
                when (n) { 1 -> println(n) }
            } finally {
                when { flag -> println(n) }
            }
            runAction { when { flag -> println(n) } }
            val action: () -> Unit = { when (n) { 1 -> println(n) } }
            action()
        }
        fun valueWithFinally(flag: Boolean): Int = try {
            1
        } finally {
            when { flag -> println(2) }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testValueContextsStillRequireExhaustiveness() throws {
        let sources = [
            "fun number(): Int = 1\nfun test(): Int = when (number()) { 1 -> 1 }",
            "class N { fun tryIt(): Int = 1 }\nfun test(n: N) { val value = when (n.tryIt()) { 1 -> 1 } }",
            "fun test(query: String): Int = when (query[0]) { '&' -> 1 }",
            "fun test(values: IntArray): Int = when (values[0]) { 1 -> 1 }",
            "fun test(n: Byte): Int = when (n) { 1.toByte() -> 1 }",
            "fun test(flag: Boolean): Int { return when { flag -> 1 } }",
            "fun test(flag: Boolean) { val value = when { flag -> 1 } }",
            "fun take(n: Int) {}\nfun test(flag: Boolean) { take(when { flag -> 1 }) }",
            "fun test(flag: Boolean): Int = if (flag) { when { flag -> 1 } } else 0",
            "fun test(flag: Boolean): Int = try { when { flag -> 1 } } catch (e: Exception) { 0 }",
            "fun test(flag: Boolean): Int = try { 0 } catch (e: Exception) { when { flag -> 1 } }",
            "fun test(flag: Boolean): Int = when { flag -> when { flag -> 1 }; else -> 0 }",
            "fun test(flag: Boolean): Int = when (flag) { true -> 0; else -> when { flag -> 1 } }",
            "fun test(flag: Boolean): Unit = when { flag -> println(1) }",
            "fun test(flag: Boolean) { val action: () -> Int = { when { flag -> 1 } } }",
        ]
        let packagedSources = sources.enumerated().map { "package value\($0.offset)\n\($0.element)" }
        try withTemporaryFiles(contents: packagedSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            for path in paths {
                let diagnostics = diagnosticsForPath(path, in: ctx)
                #expect(diagnostics.filter { $0.code == "KSWIFTK-SEMA-0004" }.count == 1)
            }
        }
    }

    @Test func testClosedDomainStatementsStillRequireExhaustiveness() throws {
        let sources = [
            "fun test(flag: Boolean) { while (flag) { when (flag) { true -> break } } }",
            "fun test(flag: Boolean?) { if (true) { when (flag) { true -> println(1); false -> println(0) } } }",
            "enum class E { A, B }\nfun test(e: E) { try { when (e) { E.A -> println(1) } } finally {} }",
            "enum class E { A, B }\nfun test(e: E?) { when { true -> when (e) { E.A -> println(1); E.B -> println(2) } } }",
            "sealed interface S\nclass A : S\nclass B : S\nfun test(s: S) { if (true) { when (s) { is A -> println(1) } } }",
            "sealed interface S\nclass A : S\nfun test(s: S?) { val action: () -> Unit = { when (s) { is A -> println(1) } } }",
            "fun flag(): Boolean = true\nfun test() { when (flag()) { true -> println(1) } }",
            "fun test(flags: BooleanArray) { when (flags[0]) { true -> println(1) } }",
            "enum class E { A, B }\nfun entry(): E = E.A\nfun test() { when (entry()) { E.A -> println(1) } }",
            "sealed interface S\nclass A : S\nclass B : S\nfun subject(): S = A()\nfun test() { when (subject()) { is A -> println(1) } }",
        ]
        let packagedSources = sources.enumerated().map { "package closed\($0.offset)\n\($0.element)" }
        try withTemporaryFiles(contents: packagedSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            for (index, path) in paths.enumerated() {
                let diagnostics = diagnosticsForPath(path, in: ctx)
                let code = index == 4 || index == 9 ? "KSWIFTK-SEMA-0071" : "KSWIFTK-SEMA-0004"
                #expect(diagnostics.contains { $0.code == code })
            }
        }
    }
}
#endif
