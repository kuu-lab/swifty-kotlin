@testable import CompilerCore
import Testing
import TestStdlibCache

/// Covers the type of an unlabeled return that exits a lambda passed to an
/// inline higher-order function. The lambda's Boolean predicate type must not
/// be used as the expected type for the returned value.
@Suite
struct InlineNonLocalReturnTypeTests {
    @Test(arguments: [
        "plain { return@outer }",
        "cross { return@outer }",
        "no { return@outer }",
        "inlineBlock { plain { return@outer } }",
        "val block = { return@outer }",
    ])
    func illegalOuterLambdaReturnIsRejected(statement: String) throws {
        let ctx = makeContextFromSource("""
        fun plain(block: () -> Unit) { block() }
        inline fun inlineBlock(block: () -> Unit) { block() }
        inline fun cross(crossinline block: () -> Unit) { block() }
        inline fun no(noinline block: () -> Unit) { block() }
        fun test() { inlineBlock outer@ { \(statement) } }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0042", in: ctx)
    }

    @Test func outerLambdaDestinationExcludesItsOwnBoundary() throws {
        let ctx = makeContextFromSource("""
        fun plain(block: () -> Unit) { block() }
        inline fun inlineBlock(block: () -> Unit) { block() }
        fun test() {
            plain outer@ {
                inlineBlock { return@outer }
            }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: ctx)))
        let bindings = try #require(ctx.sema?.bindings)
        let returns = bindings.lambdaReturnTargets.keys.filter { exprID in
            guard case let .returnExpr(_, label?, _) = ctx.ast?.arena.expr(exprID) else { return false }
            return label == ctx.interner.intern("outer")
        }
        #expect(returns.count == 1)
        let returnExpr = try #require(returns.first)
        let target = try #require(bindings.lambdaReturnTargets[returnExpr])
        let path = try #require(bindings.lambdaReturnLambdaPaths[returnExpr])
        #expect(path.count == 1)
        #expect(!path.contains(target))
    }

    @Test(arguments: [
        "plain { return }",
        "cross { return }",
        "no { return }",
        "val block = { return }",
        "inlineBlock { plain { return } }",
        "plain { inlineBlock { return } }",
        "cross { inlineBlock { return } }",
    ])
    func illegalBareReturnIsRejected(statement: String) throws {
        try withTemporaryFile(contents: """
        fun plain(block: () -> Unit) { block() }
        inline fun inlineBlock(block: () -> Unit) { block() }
        inline fun cross(crossinline block: () -> Unit) { block() }
        inline fun no(noinline block: () -> Unit) { block() }
        fun outer() { \(statement) }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0042", in: ctx)
        }
    }

    @Test(arguments: [false, true])
    func applyTwiceBareReturnIsRejected(allowDefaultStdlibLibrary: Bool) throws {
        if allowDefaultStdlibLibrary {
            TestStdlibCache.shared.prepare()
            _ = try #require(CompilerOptions.defaultStdlibLibraryPath)
        }
        let ctx = makeContextFromSource("""
        fun applyTwice(action: (Int) -> Int): Int = action(action(1))
        fun main() {
            println(applyTwice { if (it == 1) return else it * 2 })
        }
        """, emit: allowDefaultStdlibLibrary ? .executable : .kirDump,
        allowDefaultStdlibLibrary: allowDefaultStdlibLibrary)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, Comment(rawValue: diagnosticSummary(in: ctx)))
        #expect(errors.first?.code == "KSWIFTK-SEMA-0042")
    }

    @Test func bareReturnWithoutEnclosingFunctionIsRejected() throws {
        let ctx = makeContextFromSource("val block: () -> Unit = { return }")
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0042", in: ctx)
    }

    @Test(arguments: [false, true])
    func flowCollectBareReturnIsRejected(allowDefaultStdlibLibrary: Bool) throws {
        if allowDefaultStdlibLibrary {
            TestStdlibCache.shared.prepare()
            _ = try #require(CompilerOptions.defaultStdlibLibraryPath)
        }
        let ctx = makeContextFromSource("""
        import kotlinx.coroutines.flow.*
        import kotlinx.coroutines.runBlocking
        fun main() = runBlocking {
            flowOf(1, 2, 3).collect { if (it == 2) return }
        }
        """, emit: allowDefaultStdlibLibrary ? .executable : .kirDump,
        allowDefaultStdlibLibrary: allowDefaultStdlibLibrary)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0042", in: ctx)
        let sema = try #require(ctx.sema)
        let flow = try #require(sema.symbols.lookup(
            fqName: ["kotlinx", "coroutines", "flow", "Flow"].map(ctx.interner.intern)
        ))
        #expect(sema.symbols.symbol(flow)?.flags.contains(.importedLibrary) == allowDefaultStdlibLibrary)
    }

    @Test(arguments: [false, true])
    func flowCollectLabeledReturnIsAccepted(allowDefaultStdlibLibrary: Bool) throws {
        if allowDefaultStdlibLibrary {
            TestStdlibCache.shared.prepare()
            _ = try #require(CompilerOptions.defaultStdlibLibraryPath)
        }
        let ctx = makeContextFromSource("""
        import kotlinx.coroutines.flow.*
        import kotlinx.coroutines.runBlocking
        fun main() = runBlocking {
            flowOf(1, 2, 3).collect { if (it == 2) return@collect }
        }
        """, emit: allowDefaultStdlibLibrary ? .executable : .kirDump,
        allowDefaultStdlibLibrary: allowDefaultStdlibLibrary)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: ctx)))
    }

    @Test func legalReturnTargetsRemainAccepted() throws {
        let ctx = makeContextFromSource("""
        fun plain(block: () -> Unit) { block() }
        inline fun inlineBlock(block: () -> Unit) { block() }
        fun outer() {
            plain { return@plain }
            plain local@ { return@local }
            plain(fun() { return })
            plain { fun local() { return }; local() }
            inlineBlock { inlineBlock { return } }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: ctx)))
    }

    @Test func conditionalBareAndLabeledReturnsPreserveElseBranches() throws {
        try withTemporaryFile(contents: """
        fun applyTwice(action: (Int) -> Int): Int = action(action(1))
        inline fun applyTwiceInline(action: (Int) -> Int): Int = action(action(1))
        fun plainUnit(block: () -> Unit) { block() }
        fun outer() { applyTwiceInline { if (it == 1) return else it * 2 } }
        fun labeled(): Int = applyTwice { if (it == 1) return@applyTwice 5 else it * 2 }
        fun labeledUnit() { plainUnit { if (true) return@plainUnit else plainUnit {} } }
        fun anonymous(): Int = applyTwice(fun(it: Int): Int { if (it == 1) return 5 else return it * 2 })
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: ctx)))
        }
    }

    @Test(arguments: ["inline", "plain", "crossinline", "noinline"])
    func operatorAndSafeCallReturnBoundaries(mode: String) throws {
        let modifier = mode == "plain" ? "" : "inline "
        let parameterModifier = mode == "crossinline" || mode == "noinline" ? "\(mode) " : ""
        try withTemporaryFile(contents: """
        class Runner {
            \(modifier)operator fun plus(\(parameterModifier)block: () -> Unit): Runner { block(); return this }
            \(modifier)operator fun get(\(parameterModifier)block: () -> Unit): Int { block(); return 0 }
            \(modifier)operator fun set(index: Int, \(parameterModifier)block: () -> Unit) { block() }
            \(modifier)operator fun plusAssign(\(parameterModifier)block: () -> Unit) { block() }
            \(modifier)operator fun contains(\(parameterModifier)block: () -> Unit): Boolean { block(); return false }
            \(modifier)fun call(\(parameterModifier)block: () -> Unit) { block() }
        }
        class Holder { val runner = Runner() }
        class Container { operator fun get(index: Int): Runner = Runner() }
        fun binary() { Runner() + { return } }
        fun indexedGet() { Runner()[{ return }] }
        fun indexedSet() { Runner()[0] = { return } }
        fun compound() { val runner = Runner(); runner += { return } }
        fun memberCompound() { val holder = Holder(); holder.runner += { return } }
        fun indexedCompound() { Container()[0] += { return } }
        fun contains() { ({ return }) in Runner() }
        fun notContains() { ({ return }) !in Runner() }
        fun safeCall(runner: Runner?) { runner?.call { return } }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            if mode == "inline" {
                #expect(errors.isEmpty, Comment(rawValue: diagnosticSummary(in: ctx)))
            } else {
                #expect(errors.count == 9, Comment(rawValue: diagnosticSummary(in: ctx)))
                #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0042" })
            }
        }
    }

    @Test(arguments: [false, true])
    func propertyAccessorReturnBoundaries(isInline: Bool) throws {
        try withTemporaryFile(contents: """
        \(isInline ? "inline " : "")fun invokeBlock(block: () -> Unit) { block() }
        val answer: Int get() { invokeBlock { return 42 }; return 0 }
        var observed: Int = 0
            set(value) { invokeBlock { if (value == 0) return }; field = value }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            if isInline {
                #expect(errors.isEmpty, Comment(rawValue: diagnosticSummary(in: ctx)))
            } else {
                #expect(errors.count == 2, Comment(rawValue: diagnosticSummary(in: ctx)))
                #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0042" })
            }
        }
    }

    @Test func objectLiteralAccessorsHaveTheirOwnReturnTarget() throws {
        try withTemporaryFile(contents: """
        inline fun invokeBlock(block: () -> Unit) { block() }
        fun outer(): String {
            val value = object {
                val answer: Int get() { invokeBlock { return 42 }; return 0 }
                var observed: Int = 0
                    set(value) { invokeBlock { return }; field = value }
            }
            return "ok"
        }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: ctx)))
        }
    }

    @Test func functionNameLabelsUseTheEnclosingReturnType() throws {
        let ctx = makeContextFromSource("""
        inline fun invokeBlock(block: () -> Unit) { block() }
        inline fun String.tryIt(block: () -> Unit) { block() }
        inline fun predicate(block: () -> Boolean): Boolean { return block() }
        fun h() { invokeBlock { return@h } }
        fun f(s: String) { s.tryIt { return@f } }
        fun typed(): String {
            predicate { return@typed "outer" }
            return "fallback"
        }
        fun nested(): Int {
            invokeBlock { invokeBlock { return@nested 7 } }
            return -1
        }
        fun direct(): Int { return@direct 3 }
        fun withLocal(): String {
            fun local(): Int {
                invokeBlock { return@local 9 }
                return 0
            }
            local()
            return "ok"
        }
        fun withLocalExtension(): Int {
            fun Int.local(): Int {
                invokeBlock { return@local this + 1 }
                return -1
            }
            return 2.local()
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: ctx)))
        #expect(try userFunctionReturnLambdaPathCount(in: ctx) == 7)
    }

    @Test func lambdaLabelsShadowFunctionNameLabels() throws {
        let ctx = makeContextFromSource("""
        inline fun predicate(block: () -> Boolean): Boolean { return block() }
        inline fun same(block: () -> Boolean): Boolean { return block() }
        fun explicit(): String {
            predicate explicit@ { return@explicit true }
            return "ok"
        }
        fun same(): String {
            same { return@same true }
            return "ok"
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: ctx)))
        #expect(try userFunctionReturnLambdaPathCount(in: ctx) == 0)
    }

    @Test(arguments: ["value", "out", "get"])
    func softKeywordFunctionNameLabelsUseTheEnclosingReturnType(name: String) throws {
        let ctx = makeContextFromSource("""
        inline fun invokeBlock(block: () -> Unit) { block() }
        fun \(name)(): Int {
            invokeBlock { return@\(name) 9 }
            return -1
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: ctx)))
        #expect(try userFunctionReturnLambdaPathCount(in: ctx) == 1)
    }

    @Test func wrongFunctionNameLabeledReturnTypeIsRejected() throws {
        let ctx = makeContextFromSource("""
        inline fun predicate(block: () -> Boolean): Boolean { return block() }
        fun wrong(): String {
            predicate { return@wrong true }
            return "fallback"
        }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    @Test(arguments: [
        "plain { return@outer }",
        "cross { return@outer }",
        "no { return@outer }",
        "val block = { return@outer }",
        "inlineBlock { plain { return@outer } }",
        "plain { inlineBlock { return@outer } }",
        "cross { inlineBlock { return@outer } }",
        "fun local() { inlineBlock { return@outer } }; local()",
        "inlineBlock(fun() { return@outer })",
        "inlineBlock { return@missing }",
    ])
    func illegalFunctionNameReturnIsRejected(statement: String) throws {
        let ctx = makeContextFromSource("""
        fun plain(block: () -> Unit) { block() }
        inline fun inlineBlock(block: () -> Unit) { block() }
        inline fun cross(crossinline block: () -> Unit) { block() }
        inline fun no(noinline block: () -> Unit) { block() }
        fun outer() { \(statement) }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0042", in: ctx)
    }

    @Test(arguments: [false, true])
    func nonLocalReturnsUseTheEnclosingFunctionType(allowDefaultStdlibLibrary: Bool) throws {
        if allowDefaultStdlibLibrary {
            TestStdlibCache.shared.prepare()
            _ = try #require(CompilerOptions.defaultStdlibLibraryPath)
        }
        let ctx = makeContextFromSource("""
        fun firstNonLocal(source: CharSequence): Char {
            return source.first { return '!' }
        }

        fun firstConditionalNonLocal(source: CharSequence): Char {
            return source.first { ch ->
                if (ch == 'x') return '!'
                false
            }
        }

        fun trimNonLocal(source: String): String {
            source.trim { return "!" }
            return "?"
        }

        fun trimStartNonLocal(source: String): String {
            source.trimStart { return "!" }
            return "?"
        }

        fun trimEndNonLocal(source: String): String {
            source.trimEnd { return "!" }
            return "?"
        }

        fun firstStringNonLocal(source: String): Char? {
            source.first { return '!' }
            return '?'
        }

        fun firstOrNullStringNonLocal(source: String): Char? {
            source.firstOrNull { return '!' }
            return '?'
        }

        fun lastStringNonLocal(source: String): Char? {
            source.last { return '!' }
            return '?'
        }

        fun lastOrNullStringNonLocal(source: String): Char? {
            source.lastOrNull { return '!' }
            return '?'
        }

        fun singleStringNonLocal(source: String): Char? {
            source.single { return '!' }
            return '?'
        }

        fun singleOrNullStringNonLocal(source: String): Char? {
            source.singleOrNull { return '!' }
            return '?'
        }

        fun labeledPredicateReturn(source: CharSequence): Char {
            return source.first { return@first true }
        }

        fun explicitLambdaLabelReturn(source: CharSequence): Char {
            return source.first predicate@ { return@predicate true }
        }
        """, emit: allowDefaultStdlibLibrary ? .executable : .kirDump,
        allowDefaultStdlibLibrary: allowDefaultStdlibLibrary)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            Comment(rawValue: "Expected non-local return values to use the enclosing function type, got: "
                + errors.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            )
        )
    }

    @Test func wrongEnclosingReturnTypeIsRejected() throws {
        let ctx = makeContextFromSource("""
        fun wrongOuterReturnType(source: CharSequence): Char {
            source.first { return "!" }
            return '?'
        }
        """)

        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    @Test func wrongLabeledPredicateReturnTypeIsRejected() throws {
        let ctx = makeContextFromSource("""
        fun wrongLabeledReturnType(source: CharSequence): Char {
            return source.first { return@first '!' }
        }
        """)

        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    @Test func localNamedFunctionResetsTheEnclosingReturnType() throws {
        let ctx = makeContextFromSource("""
        fun localNamedFunctionReturn(source: CharSequence): String {
            fun local(): Char {
                return source.first { return '!' }
            }
            local()
            return "?"
        }
        """)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: ctx)))
    }
}

private func assertHasDiagnostic(_ code: String, in ctx: CompilationContext) {
    let found = ctx.diagnostics.diagnostics.contains { $0.code == code }
    let descriptions = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }
    #expect(found, "Expected diagnostic \(code), got: \(descriptions)")
}

private func diagnosticSummary(in ctx: CompilationContext) -> String {
    ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
}

private func userFunctionReturnLambdaPathCount(in ctx: CompilationContext) throws -> Int {
    let ast = try #require(ctx.ast)
    let sema = try #require(ctx.sema)
    let input = try #require(ctx.options.inputs.first)
    let fileID = try #require(ctx.sourceManager.fileID(forPath: input))
    return sema.bindings.functionReturnLambdaPaths.keys.filter {
        ast.arena.exprRange($0)?.start.file == fileID
    }.count
}
