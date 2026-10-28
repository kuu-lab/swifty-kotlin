#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

/// KUU-3019: a function body's type-check result, once stored, must be
/// restorable into a different compilation of the same source with different
/// raw IDs — and must be identical to what that compilation computes itself.
@Suite
struct FunctionBodySemaSnapshotTests {
    private let program = """
    class Box<T>(val value: T) { fun get(): T = value }
    fun <T> identity(x: T): T = x
    fun helper(x: Int): Int = x + 1
    fun compute(n: Int): Int {
        val box = Box(n)
        var acc = helper(box.get())
        val f = { y: Int -> y + acc }
        if (acc > 3) acc = identity(acc) else acc = f(2)
        return acc
    }
    fun other(s: String, flag: Boolean): String = if (flag) s else "none"
    """

    private func analyze(_ source: String) throws -> CompilationContext {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map(\.message))")
        return ctx
    }

    /// Function declarations by name, so snapshots can be matched across compilations.
    private func functionDecls(_ ctx: CompilationContext) throws -> [String: DeclID] {
        let ast = try #require(ctx.ast)
        var result: [String: DeclID] = [:]
        for (index, decl) in ast.arena.declarations().enumerated() {
            guard case let .funDecl(function) = decl else { continue }
            result[ctx.interner.resolve(function.name)] = DeclID(rawValue: Int32(index))
        }
        return result
    }

    private func capture(_ ctx: CompilationContext) throws -> [String: FunctionBodySemaSnapshot] {
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        var result: [String: FunctionBodySemaSnapshot] = [:]
        for (name, declID) in try functionDecls(ctx) {
            if let snapshot = FunctionBodySemaSnapshot.capture(declID: declID, ast: ast, sema: sema, interner: ctx.interner) {
                result[name] = snapshot
            }
        }
        return result
    }

    private func firstExpr(_ ctx: CompilationContext, _ name: String) throws -> Int32? {
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let declID = try #require(functionDecls(ctx)[name])
        return FunctionBodySemaScope(declID: declID, ast: ast, sema: sema)?.firstExpr
    }

    /// Restores `snapshots` into `ctx` and returns every mismatch against
    /// what that compilation's own type checker produced.
    private func mismatches(of snapshots: [String: FunctionBodySemaSnapshot], in ctx: CompilationContext) throws -> [String] {
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let decls = try functionDecls(ctx)
        var problems: [String] = []
        for (name, snapshot) in snapshots {
            guard let declID = decls[name] else { problems.append("\(name): missing"); continue }
            guard let restored = snapshot.restore(declID: declID, ast: ast, sema: sema, interner: ctx.interner) else {
                problems.append("\(name): restore failed")
                continue
            }
            problems += FunctionBodySemaSnapshot.differences(restored: restored, declID: declID, ast: ast, sema: sema)
                .map { "\(name): \($0)" }
        }
        return problems
    }

    @Test
    func capturesTheFunctionsOfARealProgram() throws {
        let snapshots = try capture(analyze(program))
        for name in ["identity", "helper", "compute", "other"] {
            let snapshot = try #require(snapshots[name], "\(name) should be representable")
            #expect(!snapshot.exprTypes.isEmpty)
        }
        let compute = try #require(snapshots["compute"])
        #expect(compute.localSymbolCount > 0, "compute declares locals")
        #expect(!compute.callBindings.isEmpty)
        #expect(!compute.identifierSymbols.isEmpty)
        let refs = compute.identifierSymbols.map(\.value)
        #expect(refs.contains { if case .local = $0 { true } else { false } }, "locals are positional")
        #expect(refs.contains { if case .lambdaParameter = $0 { true } else { false } }, "lambda parameters are lambda-relative")
        #expect(
            compute.callBindings.contains { if case .global = $0.value.chosenCallee { true } else { false } },
            "callees are referenced by name"
        )
    }

    @Test
    func snapshotSurvivesJSONRoundTrip() throws {
        let snapshots = try capture(analyze(program))
        let data = try JSONEncoder().encode(snapshots)
        let decoded = try JSONDecoder().decode([String: FunctionBodySemaSnapshot].self, from: data)
        #expect(decoded == snapshots)
    }

    @Test
    func restoringIntoAnIdenticalCompilationMatchesItsOwnTypeCheck() throws {
        let snapshots = try capture(analyze(program))
        let problems = try mismatches(of: snapshots, in: analyze(program))
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test
    func restoringIntoACompilationWithShiftedIDsMatchesItsOwnTypeCheck() throws {
        let original = try analyze(program)
        let snapshots = try capture(original)
        // Unrelated declarations ahead of the program renumber every symbol,
        // type and expression that follows.
        let shifted = try analyze("""
        class Pair2<A, B>(val a: A, val b: B)
        fun unrelated(p: Pair2<Int, String>, f: (Int) -> Boolean): Boolean = f(1) && p.a > 0
        fun more(): Int { val q = 1; val r = q + 2; return r * 3 }
        \(program)
        """)
        #expect(try firstExpr(original, "compute") != firstExpr(shifted, "compute"), "test must really shift ExprIDs")
        let problems = try mismatches(of: snapshots, in: shifted)
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test
    func restoreIsRejectedWhenTheDeclarationShapeChanged() throws {
        let snapshots = try capture(analyze(program))
        let edited = try analyze(program.replacingOccurrences(of: "fun helper(x: Int): Int = x + 1", with: "fun helper(x: Int): Int = (x + 1) * 2 - x"))
        let ast = try #require(edited.ast)
        let sema = try #require(edited.sema)
        let declID = try #require(functionDecls(edited)["helper"])
        let snapshot = try #require(snapshots["helper"])
        #expect(snapshot.restore(declID: declID, ast: ast, sema: sema, interner: edited.interner) == nil)
    }

    @Test
    func restoreFailsWhenAReferencedSymbolNoLongerExists() throws {
        let snapshots = try capture(analyze(program))
        let renamed = try analyze(program.replacingOccurrences(of: "helper", with: "helper2"))
        let ast = try #require(renamed.ast)
        let sema = try #require(renamed.sema)
        // `compute` calls `helper`; in the renamed program that callee is gone.
        let declID = try #require(functionDecls(renamed)["compute"])
        let snapshot = try #require(snapshots["compute"])
        #expect(snapshot.restore(declID: declID, ast: ast, sema: sema, interner: renamed.interner) == nil)
    }

    // MARK: - Coverage inventory

    /// Every `BindingTable` property, classified. Adding a binding map without
    /// deciding whether snapshots must carry it fails this test, so a future
    /// cache hit can never silently lose a binding that BuildKIR reads.
    private static let pendingBindings: Set<String> = [
        "annotationFactoryExpressions", "anyToStringCallableRefs", "boundClassRefExprs", "builderDSLExprIDs",
        "builderDSLKinds", "cachedContractCallsInPlaceInitializedSymbolsUnion", "callableRefKinds",
        "callableReferenceBindings", "callableTargets", "callableValueCalls", "captureSymbolsByExpr",
        "capturedLocalTypesBySymbol", "castTargetTypes", "catchClauseBindings", "charRangeExprIDs",
        "charRangeSymbolIDs", "classRefTargetTypes", "collectionExprIDs", "collectionHOFLambdaExprIDs",
        "collectionSymbolIDs", "constExprValues", "constructorDelegationCallBindings",
        "constructorDelegationTargets", "contractCallsInPlaceInitializedSymbolsByExpr",
        "coroutineLauncherLambdaExprIDs", "coroutineScopeImplicitReceiverCallExprs",
        "coroutineScopeLambdaReceiverTypes", "declSymbols", "deferredElementTypesByExpr",
        "deferredElementTypesBySymbol", "destructuringComponentCallees", "destructuringPropertyBindings",
        "directlyInvokedLambdaExprIDs", "enumEntryConstructorBindings", "enumEntryInvokeReceiverSymbols",
        "extensionPropertyGetterCalls", "findAnnotationSearchTypes", "floatingPointRangeElementTypesByExpr",
        "floatingPointRangeElementTypesBySymbol", "floatingPointRangeExprIDs", "floatingPointRangeSymbolIDs",
        "flowElementTypesByExpr", "flowElementTypesBySymbol", "flowExprIDs", "flowSymbolIDs",
        "fqnQualifiedValueExprIDs", "fqnTopLevelCallExprIDs", "functionReturnLambdaPaths",
        "functionValueExpectedTypes", "implicitExtensionReceiverSymbols", "implicitReceiverMemberNames",
        "implicitReceiverOuterReceiverSymbols", "indexedCompoundAssignElementOperatorBindings",
        "indexedCompoundAssignOperatorBindings", "inferredCallableReferenceSymbols", "invokeOperatorCallExprs",
        "invokeOperatorPropertyCalls", "isCheckTargetTypes", "lambdaReturnLambdaPaths", "lambdaReturnTargets",
        "localFunctionCaptureSymbolsBySymbol", "loopIterationBindings", "loopJumpLambdaPaths",
        "nominalFunctionExpectedTypes", "nonEscapingComparableCharLocals", "objectLiteralCaptureSymbolsByOwner",
        "objectLiteralCapturedReceiversByOwner", "objectLiteralPropertySymbolIDs", "openFloatingPointRangeExprIDs",
        "openFloatingPointRangeSymbolIDs", "pendingAnnotationTargets", "platformNullAssertionTypes",
        "primaryConstructorPropertyAnnotations", "primaryConstructorPropertyParameters",
        "primitiveOperatorCallableRefs", "primitiveUnaryOperatorCallableRefs", "rangeExprIDs", "rangeSymbolIDs",
        "rawSuspendEntryLambdaExprIDs", "samConversionExprs", "samInterfaceTypes", "samUnderlyingFunctionTypes",
        "scopeFunctionExprIDs", "scopeFunctionKinds", "sourceDeclaredExpectedTypeExprIDs",
        "stdlibSpecialCallExprIDs", "stdlibSpecialCallKinds", "superCallExprs", "typeQualifiedConstructorCallExprIDs",
        "uintRangeExprIDs", "uintRangeSymbolIDs", "ulongRangeExprIDs", "ulongRangeSymbolIDs",
        "unboundCallableRefs", "unitReturnCoercionExprs", "validatedAnnotationOptInMarkers", "whenExhaustiveness",
        "workerExecuteCallees", "workerExecuteJobRanges",
    ]

    @Test
    func everyBindingTablePropertyIsClassifiedAsCoveredOrPending() {
        let all = Set(Mirror(reflecting: BindingTable()).children.compactMap(\.label))
        let covered = FunctionBodySemaSnapshot.coveredBindings
        #expect(covered.isSubset(of: all), "covered names must exist: \(covered.subtracting(all).sorted())")
        let unclassified = all.subtracting(covered).subtracting(Self.pendingBindings)
        #expect(unclassified.isEmpty, "classify new BindingTable properties: \(unclassified.sorted())")
        let stale = Self.pendingBindings.subtracting(all)
        #expect(stale.isEmpty, "remove deleted properties from the pending list: \(stale.sorted())")
        #expect(covered.isDisjoint(with: Self.pendingBindings))
    }
}
#endif
