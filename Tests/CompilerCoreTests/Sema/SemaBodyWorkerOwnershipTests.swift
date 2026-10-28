#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

private final class OwnershipInferenceWork: @unchecked Sendable {
    let worker: SemaBodyWorker
    let file: ASTFile
    let scope: FileScope
    let function: FunDecl
    let symbol: SymbolID

    init(worker: SemaBodyWorker, file: ASTFile, scope: FileScope, function: FunDecl, symbol: SymbolID) {
        self.worker = worker
        self.file = file
        self.scope = scope
        self.function = function
        self.symbol = symbol
    }

    func run() -> [String] {
        let driver = worker.driver
        driver.declChecker.typeCheckFunctionDecl(
            function, symbol: symbol,
            ctx: worker.inferenceContext(file: file, scope: scope).with(currentDeclSymbol: symbol),
            solver: driver.solver, diagnostics: driver.diagnostics
        )
        return driver.sema.bindings.identifierSymbols.sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue):\($0.value.rawValue)" }
    }
}

@Suite
struct SemaBodyWorkerOwnershipTests {
    private func prepare(_ source: String) throws -> (TypeCheckDriver, ASTFile, FileScope) {
        let path = "/virtual/sema-ownership/input.kt"
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try runFrontend(ctx)
        try DataFlowSemaPhase().run(ctx)
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let cache = SemaCacheContext()
        let resolver = OverloadResolver()
        resolver.cacheContext = cache
        let parent = TypeCheckDriver(
            ast: ast, sema: sema, sourceManager: ctx.sourceManager,
            solver: ConstraintSolver(), resolver: resolver, dataFlow: DataFlowAnalyzer(),
            interner: ctx.interner, diagnostics: ctx.diagnostics, semaCacheContext: cache
        )
        let file = try #require(ast.files.first)
        let scopes = parent.scopeBuilder.buildFileScopes(
            ast: ast, sema: sema, interner: ctx.interner, sourceManager: ctx.sourceManager
        )
        return (parent, file, try #require(scopes[file.fileID.rawValue]))
    }

    @Test(arguments: [2, 4])
    func localLambdaAndObjectInferenceNeverMutatesParentOrSibling(jobs: Int) throws {
        let (parent, file, scope) = try prepare("""
        fun owned(x: Int): Int {
            val y = x + 1
            val f: (Int) -> Int = { z -> y + z }
            val o = object { fun read(): Int = y }
            return f(o.read())
        }
        """)
        let declaration = try #require(file.topLevelDecls.first)
        guard case let .funDecl(function)? = parent.ast.arena.decl(declaration) else {
            Issue.record("Expected function")
            return
        }
        let symbol = try #require(parent.sema.bindings.declSymbols[declaration])
        let initialSymbols = parent.sema.symbols.symbolCount
        let initialTypes = parent.sema.types.workerTypeKinds(since: 0)
        let initialStrings = parent.interner.snapshotValues()
        let initialAST = parent.ast.arena.snapshot()
        let initialBindings = parent.sema.bindings.exprTypes
        // Deferred inference contexts deliberately remain module-owned. Copying
        // them would carry the parent driver, Sema and scopes into a worker.
        parent.deferredInferredReturnFunctions.insert(symbol)
        parent.deferredInferredProperties.insert(symbol)
        let workers = (0..<jobs).map { _ in SemaBodyWorker(parent: parent, copyingBindings: true) }
        let tasks = workers.map {
            OwnershipInferenceWork(worker: $0, file: file, scope: scope, function: function, symbol: symbol)
        }
        let signatures = try SemaPerFileExecutor.collect(count: jobs, jobs: jobs) { index in
            tasks[index].run()
        }
        for worker in workers {
            let driver = worker.driver
            #expect(!driver.diagnostics.hasError, "\(driver.diagnostics.diagnostics)")
            #expect(driver.sema.types.symbolTable === driver.sema.symbols)
            #expect(driver.semaCacheContext !== parent.semaCacheContext)
            #expect(driver.resolver.cacheContext === driver.semaCacheContext)
            #expect(driver.deferredInferredReturnFunctions.isEmpty)
            #expect(driver.deferredInferredProperties.isEmpty)
            #expect(driver.sema.symbols.symbolCount > initialSymbols)
            #expect(!driver.sema.bindings.captureSymbolsByExpr.isEmpty)
            #expect(!driver.sema.bindings.objectLiteralCaptureSymbolsByOwner.isEmpty)
            #expect(!driver.sema.bindings.hasOnlyIndependentScalarBindings)
            let syntheticParameters = driver.sema.bindings.identifierSymbols.values.filter { $0.rawValue <= -1_000_000 }
            #expect(!syntheticParameters.isEmpty)
            for parameter in syntheticParameters {
                #expect(driver.sema.symbols.propertyType(for: parameter) != nil)
                #expect(parent.sema.symbols.propertyType(for: parameter) == nil)
            }
        }
        #expect(signatures.allSatisfy { $0 == signatures[0] })
        #expect(parent.sema.symbols.symbolCount == initialSymbols)
        #expect(parent.sema.types.workerTypeKinds(since: 0) == initialTypes)
        #expect(parent.interner.snapshotValues() == initialStrings)
        #expect(parent.ast.arena.snapshot().expressions == initialAST.expressions)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(try encoder.encode(parent.ast.arena.snapshot().declarations) == encoder.encode(initialAST.declarations))
        #expect(parent.sema.bindings.exprTypes == initialBindings)
        #expect(parent.sema.bindings.captureSymbolsByExpr.isEmpty)
        #expect(parent.sema.bindings.objectLiteralCaptureSymbolsByOwner.isEmpty)
        #expect(parent.diagnostics.diagnostics.isEmpty)
        #expect(parent.deferredInferredReturnFunctions == [symbol])
        #expect(parent.deferredInferredProperties == [symbol])
        let untouched = SemaBodyWorker(parent: parent, copyingBindings: true)
        #expect(untouched.driver.sema.symbols.symbolCount == initialSymbols)
        #expect(untouched.driver.sema.bindings.captureSymbolsByExpr.isEmpty)
    }

    @Test
    func snapshotsPreserveSetterVisibilityImportedIdentityAndBounds() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let nominal = symbols.define(kind: .class, name: interner.intern("Owner"), fqName: [], declSite: nil, visibility: .public)
        symbols.setPropertySetterVisibility(.private, for: nominal)
        symbols.markImportedStdlibSymbol(nominal)
        let types = TypeSystem()
        types.symbolTable = symbols
        types.unitClassSymbol = nominal
        types.setNominalTypeParameterUpperBounds([[types.stringType]], for: nominal)
        let captured = types.makeCapturedType(parameter: nominal, lower: types.nothingType, upper: types.stringType)
        let workerSymbols = symbols.makeSemaWorkerSymbols()
        let workerTypes = types.makeSemaWorkerTypes()
        #expect(workerSymbols.propertySetterVisibility(for: nominal) == .private)
        #expect(workerSymbols.isImportedStdlibSymbol(nominal))
        #expect(workerTypes.unitClassSymbol == nominal)
        #expect(workerTypes.nominalTypeParameterUpperBounds(for: nominal) == [[types.stringType]])
        // Resetting the capture ordinal would alias this fresh existential to
        // the already interned capture in the snapshot prefix.
        let next = workerTypes.makeCapturedType(parameter: nominal, lower: types.nothingType, upper: types.stringType)
        #expect(next != captured)
        #expect(types.internedTypeCount + 1 == workerTypes.internedTypeCount)
        workerSymbols.setPropertySetterVisibility(.public, for: nominal)
        workerTypes.setNominalTypeParameterUpperBounds([[types.intType]], for: nominal)
        #expect(symbols.propertySetterVisibility(for: nominal) == .private)
        #expect(types.nominalTypeParameterUpperBounds(for: nominal) == [[types.stringType]])
    }

    @Test
    func bindingSnapshotsOwnCaptureCallableAndPendingAnnotationState() {
        let parent = BindingTable()
        let expr = ExprID(rawValue: 1)
        let symbol = SymbolID(rawValue: 2)
        let decl = DeclID(rawValue: 3)
        let call = CallBinding(chosenCallee: symbol, substitutedTypeArguments: [TypeID(rawValue: 8)], parameterMapping: [0: 0])
        parent.bindCallableReference(expr, binding: call)
        parent.bindCaptureSymbols(expr, symbols: [symbol])
        parent.bindCapturedLocalType(symbol, type: TypeID(rawValue: 8))
        let workerReceiverType = TypeID(rawValue: 10)
        parent.mergeIndependentScalarExpressions(
            types: [:], identifiers: [:], typeMapping: [TypeID(rawValue: 9): workerReceiverType],
            compoundAssignReceiverTypes: [expr: TypeID(rawValue: 9)]
        )
        parent.deferAnnotationTargets(decl, lexicalEnclosingFQNames: [[InternedString(rawValue: 4)]])
        parent.recordValidatedAnnotationOptIn(usageID: "annotation", markers: [symbol])
        let worker = parent.makeSemaWorkerBindings()
        #expect(worker.callableReferenceBindings[expr]?.chosenCallee == symbol)
        #expect(worker.compoundAssignReceiverType(for: expr) == workerReceiverType)
        #expect(worker.captureSymbolsByExpr[expr] == [symbol])
        #expect(worker.capturedLocalTypesBySymbol[symbol] == TypeID(rawValue: 8))
        #expect(worker.validatedAnnotationOptInMarkers["annotation"] == [symbol])
        #expect(worker.takePendingAnnotationTargets()[decl] == [[InternedString(rawValue: 4)]])
        worker.bindCallableReference(expr, binding: nil)
        worker.bindCompoundAssignReceiverType(expr, type: TypeID(rawValue: 12))
        worker.bindCapturedLocalType(symbol, type: TypeID(rawValue: 9))
        #expect(parent.callableReferenceBindings[expr]?.chosenCallee == symbol)
        #expect(parent.compoundAssignReceiverType(for: expr) == workerReceiverType)
        #expect(parent.capturedLocalTypesBySymbol[symbol] == TypeID(rawValue: 8))
        #expect(parent.takePendingAnnotationTargets()[decl] == [[InternedString(rawValue: 4)]])
    }
}
#endif
