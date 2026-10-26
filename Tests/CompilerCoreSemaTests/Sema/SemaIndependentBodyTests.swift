#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct SemaIndependentBodyTests {
    private func analyze(_ sources: [String], jobs: Int, enabled: Bool = true, parallelFrontend: Bool = false) throws -> CompilationContext {
        let paths = sources.indices.map { "/virtual/sema-independent/input\($0).kt" }
        let ctx = makeCompilationContext(
            inputs: paths,
            frontendFlags: ["jobs=\(parallelFrontend ? jobs : 1)"],
            includeStdlib: false
        )
        for (path, source) in zip(paths, sources) {
            _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        }
        try runFrontend(ctx)
        // BuildAST currently allocates into a shared arena, so frontend jobs
        // can change ExprIDs before Sema starts. Freeze that input when testing
        // the Sema allocator itself, including ExprID-based synthetic names.
        var options = ctx.options
        options.frontendFlags = ["jobs=\(jobs)"] + (enabled ? ["sema-parallel"] : [])
        let semaContext = CompilationContext(
            options: options, sourceManager: ctx.sourceManager,
            diagnostics: ctx.diagnostics, interner: ctx.interner
        )
        semaContext.tokens = ctx.tokens
        semaContext.tokensByFile = ctx.tokensByFile
        semaContext.storeSyntaxTrees(ctx.syntaxTrees)
        semaContext.ast = ctx.ast
        try SemaPhase().run(semaContext)
        return semaContext
    }

    private func bindings(_ ctx: CompilationContext) throws -> [String] {
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        return sema.bindings.exprTypes.compactMap { expr, type in
            guard let range = ast.arena.exprRange(expr) else { return nil }
            let symbol = sema.bindings.identifierSymbols[expr]?.rawValue ?? -1
            let callee = sema.bindings.callBindings[expr]?.chosenCallee.rawValue ?? -1
            return "\(range.start.file.rawValue):\(range.start.offset):\(range.end.offset):\(type.rawValue):\(symbol):\(callee)"
        }.sorted()
    }

    @Test(arguments: [2, 4])
    func scalarBodiesPreserveTypesSymbolsAndDiagnostics(jobs: Int) throws {
        let sources = [
            "fun square(x: Int): Int = x * x + 1\nfun branch(x: Int): Int = if (x > 0) x else 0",
            "fun truth(x: Boolean): Boolean = x && true\nfun widen(x: Long): Long = x + 1",
            "fun text(x: String): String = x\nfun bad(): Int = \"wrong\"",
        ]
        let serial = try analyze(sources, jobs: 1)
        for _ in 0..<3 {
            let parallel = try analyze(sources, jobs: jobs)
            #expect(parallel.sema?.independentBodyCount == 4)
            #expect(try bindings(parallel) == bindings(serial))
            #expect(parallel.diagnostics.diagnostics == serial.diagnostics.diagnostics)
        }
        #expect(serial.diagnostics.hasError)
    }

    @Test
    func parallelismRequiresExplicitOptIn() throws {
        let ctx = try analyze(["fun a(x: Int): Int = x + 1", "fun b(x: Int): Int = x * 2"], jobs: 4, enabled: false)
        #expect(ctx.sema?.independentBodyCount == 0)
        #expect(!ctx.diagnostics.hasError)
    }

    @Test(arguments: [2, 4])
    func inferredDeclarationsAndLocalBodiesRetainModuleBarriers(jobs: Int) throws {
        let sources = [
            """
            package isolation
            fun first(): Int = later()
            fun independent(x: Int): Int = x + 1
            fun local(x: Int): Int { val y = x + 1; return y }
            """,
            """
            package isolation
            val seed = 40
            fun later() = seed + 2
            fun another(x: Int): Int = x * 2
            """,
        ]
        let serial = try analyze(sources, jobs: 1)
        let parallel = try analyze(sources, jobs: jobs)
        #expect(!parallel.diagnostics.hasError)
        #expect(parallel.sema?.independentBodyCount == 3)
        #expect(parallel.diagnostics.diagnostics == serial.diagnostics.diagnostics)
        #expect(try bindings(parallel) == bindings(serial))
    }

    private func symbolRecords(_ ctx: CompilationContext) throws -> [String] {
        let sema = try #require(ctx.sema)
        return sema.symbols.allSymbols().map { symbol in
            "\(symbol.id.rawValue):\(symbol.kind):\(symbol.name.rawValue):\(symbol.fqName.map(\.rawValue)):\(symbol.flags.rawValue):\(sema.symbols.propertyType(for: symbol.id)?.rawValue ?? -1)"
        }
    }

    @Test(arguments: [2, 4])
    func scalarLocalAllocationsJoinInDeclarationOrder(jobs: Int) throws {
        let sources = [
            """
            fun first(x: Int): Int { val y = x + 1; return y * 2 }
            fun serial(x: Int): Int { val f = { x + 1 }; return f() }
            fun second(x: Long): Long { var y = x; y = y + 2; return y }
            """,
            """
            fun branch(x: Int): Int { var y = x; if (x > 0) { val z = x + 2; y = z }; return y }
            fun last(x: Int): Int { val a = x + 1; val b = a * 2; return b }
            """,
        ]
        let serial = try analyze(sources, jobs: 1)
        #expect(!serial.diagnostics.hasError, "\(serial.diagnostics.diagnostics)")
        for _ in 0..<3 {
            let parallel = try analyze(sources, jobs: jobs)
            #expect(parallel.sema?.independentBodyCount == 4)
            #expect(parallel.diagnostics.diagnostics == serial.diagnostics.diagnostics)
            #expect(try bindings(parallel) == bindings(serial))
            #expect(try symbolRecords(parallel) == symbolRecords(serial))
            #expect(parallel.interner.snapshotValues() == serial.interner.snapshotValues())
            let types = try #require(parallel.sema?.types)
            let serialTypes = try #require(serial.sema?.types)
            #expect(types.workerTypeKinds(since: 0) == serialTypes.workerTypeKinds(since: 0))
        }
    }

    @Test(arguments: [2, 4])
    func scalarLocalTypeAnnotationsJoinWithCanonicalBindings(jobs: Int) throws {
        let sources = [
            "typealias Count = Int\nfun count(x: Int): Int { val y: Count = x + 1; var z: Int = y; z = z + 2; return z }",
            "fun text(x: String): String { val copy: String = x; return copy }",
            "fun other(x: Int): Int { val y: Int = x * 2; return y }",
        ]
        let serial = try analyze(sources, jobs: 1)
        #expect(!serial.diagnostics.hasError, "\(serial.diagnostics.diagnostics)")
        for _ in 0..<3 {
            let parallel = try analyze(sources, jobs: jobs)
            #expect(parallel.sema?.independentBodyCount == 3)
            #expect(parallel.diagnostics.diagnostics == serial.diagnostics.diagnostics)
            #expect(try bindings(parallel) == bindings(serial))
            #expect(try symbolRecords(parallel) == symbolRecords(serial))
            #expect(parallel.sema?.bindings.sourceDeclaredExpectedTypeExprIDs == serial.sema?.bindings.sourceDeclaredExpectedTypeExprIDs)
            #expect(parallel.interner.snapshotValues() == serial.interner.snapshotValues())
            let types = try #require(parallel.sema?.types)
            let serialTypes = try #require(serial.sema?.types)
            #expect(types.workerTypeKinds(since: 0) == serialTypes.workerTypeKinds(since: 0))
        }
    }

    @Test(arguments: [2, 4])
    func invalidScalarLocalAnnotationsFallBackToSerialAnalysis(jobs: Int) throws {
        let sources = [
            "fun invalid(x: Int): Int { val text: String = x; return x }",
            "fun good(x: Int): Int { val y: Int = x + 1; return y }",
        ]
        let serial = try analyze(sources, jobs: 1)
        #expect(serial.diagnostics.hasError)
        let parallel = try analyze(sources, jobs: jobs)
        #expect(parallel.sema?.independentBodyCount == 1)
        #expect(parallel.diagnostics.diagnostics == serial.diagnostics.diagnostics)
        #expect(try bindings(parallel) == bindings(serial))
        #expect(try symbolRecords(parallel) == symbolRecords(serial))
        #expect(parallel.sema?.bindings.sourceDeclaredExpectedTypeExprIDs == serial.sema?.bindings.sourceDeclaredExpectedTypeExprIDs)
        #expect(parallel.interner.snapshotValues() == serial.interner.snapshotValues())
    }

    @Test(arguments: [2, 4])
    func rejectedLocalFilesLeaveNoAllocationsOrDiagnostics(jobs: Int) throws {
        let sources = [
            """
            fun good(x: Int): Int { val y = x + 1; return y }
            fun bad(x: Int): Int { val y = x; y = 2; return y }
            """,
            "fun other(x: Int): Int { val y = x * 2; return y }",
            """
            fun capture(x: Int): Int { val y = x; val f = { y + 1 }; return f() }
            fun nominal(x: Int): Int { val o = object { val y = x }; return o.y }
            """,
        ]
        let serial = try analyze(sources, jobs: 1)
        #expect(serial.diagnostics.hasError)
        for _ in 0..<3 {
            let parallel = try analyze(sources, jobs: jobs)
            #expect(parallel.sema?.independentBodyCount == 1)
            #expect(parallel.diagnostics.diagnostics == serial.diagnostics.diagnostics)
            #expect(try bindings(parallel) == bindings(serial))
            #expect(try symbolRecords(parallel) == symbolRecords(serial))
            #expect(parallel.interner.snapshotValues() == serial.interner.snapshotValues())
        }
    }

    @Test(arguments: [2, 4])
    func laterLocalNamesCannotHideModuleDependencies(jobs: Int) throws {
        let sources = [
            """
            val seed = 40
            fun beforeLocal(): Int { val y = seed; val seed = 2; return y + seed }
            """,
            "fun other(x: Int): Int { val y = x + 1; return y }",
        ]
        let serial = try analyze(sources, jobs: 1)
        let parallel = try analyze(sources, jobs: jobs)
        #expect(parallel.sema?.independentBodyCount == 1)
        #expect(parallel.diagnostics.diagnostics == serial.diagnostics.diagnostics)
        #expect(try bindings(parallel) == bindings(serial))
        #expect(try symbolRecords(parallel) == symbolRecords(serial))
    }

    @Test(arguments: [2, 4])
    func wholeFrontendPreservesSourcePositionBindingsForScalarLocals(jobs: Int) throws {
        let sources = [
            "fun first(x: Int): Int { val y = x + 1; return y * 2 }",
            "fun second(x: Int): Int { var y = x; y = y + 2; return y }",
        ]
        let serial = try analyze(sources, jobs: 1)
        let parallel = try analyze(sources, jobs: jobs, parallelFrontend: true)
        #expect(parallel.sema?.independentBodyCount == 2)
        #expect(parallel.diagnostics.diagnostics == serial.diagnostics.diagnostics)
        #expect(try bindings(parallel) == bindings(serial))
    }

    @Test(arguments: [2, 4])
    func operatorExtensionUsesRealImportScope(jobs: Int) throws {
        let sources = [
            """
            operator fun Char.plus(s: String): Int = 99
            fun extension(c: Char, s: String): String = c + s
            """,
            "fun independent(x: Int): Int = x + 1",
        ]
        let serial = try analyze(sources, jobs: 1)
        let parallel = try analyze(sources, jobs: jobs)
        #expect(serial.diagnostics.hasError)
        #expect(parallel.diagnostics.diagnostics == serial.diagnostics.diagnostics)
        #expect(try bindings(parallel) == bindings(serial))
    }

    @Test(arguments: [2, 4])
    func inferredOperatorAndNestedAliasesRemainAuthoritative(jobs: Int) throws {
        let sources = [
            """
            operator fun Char.plus(s: String) = 99
            typealias Alias = Owner.Nested
            fun take(x: Alias): Int = 1
            fun extension(c: Char, s: String): String = c + s
            fun scalar(x: Int): Int = x + 1
            """,
            """
            class Owner { class Nested }
            fun other(x: Int): Int = x * 2
            """,
        ]
        let serial = try analyze(sources, jobs: 1)
        let parallel = try analyze(sources, jobs: jobs)
        #expect(parallel.diagnostics.diagnostics == serial.diagnostics.diagnostics)
        #expect(try bindings(parallel) == bindings(serial))
    }

    @Test
    func deepScalarBodiesUseIndependentArenaAndLargeStack() throws {
        let expression = Array(repeating: "x * x", count: 80).joined(separator: " + ")
        let sources = [
            "fun deep(x: Int): Int = \(expression)",
            "fun other(x: Int): Int = x + 1",
        ]
        let serial = try analyze(sources, jobs: 1)
        let parallel = try analyze(sources, jobs: 4)
        #expect(!parallel.diagnostics.hasError)
        #expect(parallel.sema?.independentBodyCount == 2)
        #expect(try bindings(parallel) == bindings(serial))
    }

    @Test
    func newTypeIDsStayOnSerialPath() throws {
        // The two branches create a nullable/incompatible LUB in the worker.
        let sources = [
            "fun branch(x: Boolean): Int = if (x) 1 else \"wrong\"",
            "fun other(x: Int): Int = x + 1",
        ]
        let serial = try analyze(sources, jobs: 1)
        let parallel = try analyze(sources, jobs: 4)
        #expect(serial.diagnostics.hasError)
        #expect(try bindings(parallel) == bindings(serial))
        #expect(parallel.diagnostics.diagnostics == serial.diagnostics.diagnostics)
    }

    @Test
    func diagnosticsPolicyIsWorkerLocalAndLimitsApplyAtJoin() {
        let parent = DiagnosticEngine(maxDiagnosticsPerFile: 1)
        let range = SourceRange(
            start: SourceLocation(file: FileID(rawValue: 0), offset: 0),
            end: SourceLocation(file: FileID(rawValue: 0), offset: 20)
        )
        parent.addSuppression(code: "KSWIFTK-TYPE-0002", range: range)
        let worker = parent.makeSemaWorkerDiagnostics()
        worker.error("KSWIFTK-TYPE-0002", "suppressed", range: range)
        #expect(worker.diagnostics.isEmpty)
        let checkpoint = worker.checkpoint()
        worker.error("KSWIFTK-TYPE-0003", "speculative", range: range)
        worker.rollback(to: checkpoint)
        #expect(parent.diagnostics.isEmpty)
        worker.error("KSWIFTK-TYPE-0003", "first", range: range)
        worker.error("KSWIFTK-TYPE-0004", "second", range: range)
        for diagnostic in worker.diagnostics { parent.emit(diagnostic) }
        #expect(parent.diagnostics.map(\.code) == ["KSWIFTK-TYPE-0003", "KSWIFTK-PIPELINE-0005"])
    }

    @Test
    func canonicalTypeJoinRewritesNestedWorkerIDs() throws {
        let types = TypeSystem()
        let worker = types.makeSemaWorkerTypes()
        let prefix = types.internedTypeCount
        let local = worker.make(.classType(ClassType(classSymbol: SymbolID(rawValue: 123))))
        let function = worker.make(.functionType(FunctionType(
            contextReceivers: [local], receiver: local, params: [local],
            returnType: local, isSuspend: true, isCallableReference: true,
            nullability: .nullable, throws: [local]
        )))
        // An intervening serial declaration consumes the first local ordinal.
        _ = types.make(.classType(ClassType(classSymbol: SymbolID(rawValue: 456))))
        let mapping = types.mergeWorkerTypes(worker.workerTypeKinds(since: prefix), startingAt: prefix)
        let canonical = try #require(mapping[local])
        #expect(canonical != local)
        #expect(types.kind(of: mapping[function] ?? .invalid) == .functionType(FunctionType(
            contextReceivers: [canonical], receiver: canonical, params: [canonical],
            returnType: canonical, isSuspend: true, isCallableReference: true,
            nullability: .nullable, throws: [canonical]
        )))
        #expect(types.mergeWorkerTypes(worker.workerTypeKinds(since: prefix), startingAt: prefix) == mapping)
    }

    @Test
    func nonScalarBindingWritesRejectWorkerDelta() {
        let delta = BindingTable()
        let expr = ExprID(rawValue: 0)
        delta.bindExprType(expr, type: TypeID(rawValue: 8))
        delta.bindIdentifier(expr, symbol: SymbolID(rawValue: 1))
        #expect(delta.hasOnlyIndependentScalarBindings)
        delta.bindWorkerExecuteJobRange(expr, range: SourceRange(
            start: SourceLocation(file: FileID(rawValue: 0), offset: 0),
            end: SourceLocation(file: FileID(rawValue: 0), offset: 1)
        ))
        #expect(!delta.hasOnlyIndependentScalarBindings)
    }

    @Test
    func sourceDeclaredExpectedTypeMarkersAreAllowedOnlyForBodyExpressions() {
        let expr = ExprID(rawValue: 7)
        let outsideBody = ExprID(rawValue: 8)
        let delta = BindingTable()
        delta.markSourceDeclaredExpectedType(expr)
        #expect(!delta.hasOnlyIndependentScalarBindings)
        #expect(delta.hasOnlyIndependentScalarBindings(allowingSourceDeclaredExpectedTypeExprIDs: [expr]))
        #expect(!delta.hasOnlyIndependentScalarBindings(allowingSourceDeclaredExpectedTypeExprIDs: [outsideBody]))
    }

    @Test
    func pendingAnnotationAndCallableReferenceWritesRejectWorkerDelta() {
        let pending = BindingTable()
        pending.deferAnnotationTargets(DeclID(rawValue: 0), lexicalEnclosingFQNames: [])
        #expect(!pending.hasOnlyIndependentScalarBindings)
        let callable = BindingTable()
        callable.bindCallableReference(ExprID(rawValue: 0), binding: CallBinding(
            chosenCallee: SymbolID(rawValue: 1), substitutedTypeArguments: [], parameterMapping: [:]
        ))
        #expect(!callable.hasOnlyIndependentScalarBindings)
        let annotation = BindingTable()
        annotation.recordValidatedAnnotationOptIn(usageID: "annotation", markers: [SymbolID(rawValue: 1)])
        #expect(!annotation.hasOnlyIndependentScalarBindings)
    }
}

private final class SemaRunnerProbe: @unchecked Sendable {
    let condition = NSCondition()
    var active = 0
    var peak = 0
    var completed: Set<Int> = []
    var arrived = 0

    func run(_ index: Int, participants: Int) -> Bool {
        condition.lock()
        active += 1
        arrived += 1
        peak = max(peak, active)
        condition.broadcast()
        let deadline = Date(timeIntervalSinceNow: 5)
        while arrived < participants {
            if !condition.wait(until: deadline) { break }
        }
        let overlapped = arrived >= participants
        active -= 1
        completed.insert(index)
        condition.unlock()
        return overlapped
    }
}

@Suite
struct SemaPerFileExecutorTests {
    @Test(arguments: [1, 2, 4])
    func boundsConcurrencyAndOrdersResults(jobs: Int) throws {
        let probe = SemaRunnerProbe()
        let results = try SemaPerFileExecutor.collect(count: 12, jobs: jobs) { index in
            #expect(probe.run(index, participants: jobs))
            #if canImport(Darwin)
            #expect(Thread.current.stackSize >= 32 << 20)
            #endif
            return index
        }
        #expect(results == Array(0..<12))
        #expect(probe.peak == jobs)
        #expect(probe.completed.count == 12)
        #expect(probe.active == 0)
    }

    @Test
    func joinsAllTasksBeforeRethrowingFirstError() {
        enum Failure: Error, Equatable { case at(Int) }
        let probe = SemaRunnerProbe()
        #expect(throws: Failure.at(1)) {
            let _: [Int] = try SemaPerFileExecutor.collect(count: 12, jobs: 4) { index in
                _ = probe.run(index, participants: 4)
                if index == 1 || index == 3 { throw Failure.at(index) }
                return index
            }
        }
        #expect(probe.completed.count == 12)
        #expect(probe.active == 0)
    }
}
#endif
