#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct SemaIndependentBodyTests {
    private func analyze(_ sources: [String], jobs: Int, enabled: Bool = true) throws -> CompilationContext {
        let paths = sources.indices.map { "/virtual/sema-independent/input\($0).kt" }
        let ctx = makeCompilationContext(
            inputs: paths,
            frontendFlags: ["jobs=\(jobs)"] + (enabled ? ["sema-parallel"] : []),
            includeStdlib: false
        )
        for (path, source) in zip(paths, sources) {
            _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        }
        try runFrontend(ctx)
        try SemaPhase().run(ctx)
        return ctx
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
