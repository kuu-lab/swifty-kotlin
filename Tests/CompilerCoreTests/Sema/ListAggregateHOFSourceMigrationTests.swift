@testable import CompilerCore
import Testing

/// KSP-501/KSP-426: List aggregate and extrema functions are bundled Kotlin
/// source definitions rather than residual synthetic runtime declarations.
@Suite
struct ListAggregateHOFSourceMigrationTests {
    private let migratedDefinitions: [(name: String, sourcePath: String)] = [
        ("sumOf", "__bundled_kotlin/collections/ListAggregateHOF.kt"),
        ("maxByOrNull", "__bundled_kotlin/collections/ListExtremaHOF.kt"),
        ("minByOrNull", "__bundled_kotlin/collections/ListExtremaHOF.kt"),
    ]

    @Test
    func residualCollectionsSourceIsEmpty() {
        #expect(BundledStdlib.kotlinCollectionsSource.isEmpty)
    }

    @Test
    func migratedAggregateFunctionsAreBundledSourceDefinitions() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let packageFQName = ["kotlin", "collections"].map(ctx.interner.intern)

        for definition in migratedDefinitions {
            let name = definition.name
            let fqName = packageFQName + [ctx.interner.intern(name)]
            let sourceSymbols = sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .function,
                      !symbol.flags.contains(.synthetic),
                      let fileID = sema.symbols.sourceFileID(for: symbolID)
                else {
                    return false
                }
                return ctx.sourceManager.path(of: fileID) == definition.sourcePath
            }

            #expect(!sourceSymbols.isEmpty, "Expected \(name) to be declared in \(definition.sourcePath)")
            #expect(
                sourceSymbols.allSatisfy { sema.symbols.functionSignature(for: $0)?.receiverType != nil },
                "Expected \(name) bundled source definitions to be List extension functions"
            )
            #expect(
                sourceSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil },
                "Expected \(name) bundled source definitions to avoid direct C external links"
            )
        }
    }

    @Test
    func migratedAggregateFunctionsHaveNoResidualDuplicate() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let packageFQName = ["kotlin", "collections"].map(ctx.interner.intern)

        for definition in migratedDefinitions {
            let name = definition.name
            let fqName = packageFQName + [ctx.interner.intern(name)]
            let declaringPaths = Set(sema.symbols.lookupAll(fqName: fqName).compactMap { symbolID -> String? in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .function,
                      !symbol.flags.contains(.synthetic),
                      let fileID = sema.symbols.sourceFileID(for: symbolID)
                else {
                    return nil
                }
                return ctx.sourceManager.path(of: fileID)
            })

            #expect(
                !declaringPaths.contains("__bundled_kotlin_collections_stdlib.kt"),
                "Expected \(name) to no longer be declared by the residual bundled collections source"
            )
        }
    }

    @Test
    func listAggregateCallsTypeCheckCleanly() throws {
        let source = """
        fun sample(values: List<String>) {
            values.sumOf { value -> value.length }
            values.maxByOrNull { value -> value.length }
            values.minByOrNull { value -> value.length }
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected List aggregate source calls to type-check cleanly, got: \(aggregateDiagnosticSummary(in: ctx))"
        )
    }

    @Test
    func listSumOfSelectsNumericSourceOverloads() throws {
        let source = """
        fun sample(values: List<Int>) {
            values.sumOf { it }
            values.sumOf { it.toLong() }
            values.sumOf { it.toDouble() }
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected List.sumOf numeric overloads to type-check cleanly, got: \(aggregateDiagnosticSummary(in: ctx))"
        )

        let sumCalls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .memberCall(_, callee, _, _, _) = ast.arena.expr(exprID),
                  ctx.interner.resolve(callee) == "sumOf"
            else {
                return nil
            }
            return exprID
        }
        #expect(sumCalls.count == 3)
        let expectedTypes = [sema.types.intType, sema.types.longType, sema.types.doubleType]
        for (call, expectedType) in zip(sumCalls, expectedTypes) {
            #expect(sema.bindings.exprType(for: call) == expectedType)
            guard let chosenCallee = sema.bindings.callBinding(for: call)?.chosenCallee,
                  let signature = sema.symbols.functionSignature(for: chosenCallee)
            else {
                Issue.record("Expected List.sumOf call to resolve to a source-backed function")
                continue
            }
            #expect(sema.symbols.isSourceBackedSymbol(chosenCallee))
            #expect(signature.returnType == expectedType)
            guard let parameterType = signature.parameterTypes.first else {
                Issue.record("Expected List.sumOf selector parameter")
                continue
            }
            guard case let .functionType(selectorType) = sema.types.kind(of: parameterType) else {
                Issue.record("Expected List.sumOf selector parameter to be a function")
                continue
            }
            #expect(selectorType.returnType == expectedType)
        }
    }

    /// BUG-256 sibling: `List<T>.sumOf` (`ListAggregateHOF.kt`) only declares
    /// Int/Long/Double overloads. Before this fix, a UInt/ULong selector on a
    /// concrete List receiver never matched that set -- the fallback to the
    /// generic `Iterable<T>.sumOf` family (`ListCollectionOps.kt`) was itself
    /// unreachable for List-like receivers, and its overload-selection filter
    /// compared each candidate's *unsubstituted* type parameter against the
    /// concrete element type, which can never match. The call silently
    /// arity-matched onto the wrong (`Int`) overload instead: it linked, but
    /// `listOf("a").sumOf { UInt.MAX_VALUE }` printed `-1` (the same 32 bits
    /// reinterpreted as `Int`) instead of `4294967295`.
    @Test
    func listSumOfFallsBackToIterableSourceForUnsignedSelectorTypes() throws {
        let source = """
        fun sample(values: List<Int>) {
            values.sumOf { it.toUInt() }
            values.sumOf { it.toULong() }
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected List.sumOf unsigned overloads to type-check cleanly, got: \(aggregateDiagnosticSummary(in: ctx))"
        )

        let sumCalls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .memberCall(_, callee, _, _, _) = ast.arena.expr(exprID),
                  ctx.interner.resolve(callee) == "sumOf"
            else {
                return nil
            }
            return exprID
        }
        #expect(sumCalls.count == 2)
        let expectedTypes = [sema.types.uintType, sema.types.ulongType]
        for (call, expectedType) in zip(sumCalls, expectedTypes) {
            #expect(sema.bindings.exprType(for: call) == expectedType)
            guard let chosenCallee = sema.bindings.callBinding(for: call)?.chosenCallee,
                  let signature = sema.symbols.functionSignature(for: chosenCallee)
            else {
                Issue.record("Expected List.sumOf call with an unsigned selector to resolve to a real callee, not leak a bare `sumOf` link name")
                continue
            }
            #expect(sema.symbols.isSourceBackedSymbol(chosenCallee))
            #expect(signature.returnType == expectedType)
            // The bundled List<Int>.sumOf overload set has no UInt/ULong
            // member; the resolved callee must be the generic Iterable<T>
            // fallback (ListCollectionOps.kt), not ListAggregateHOF.kt.
            if let fileID = sema.symbols.sourceFileID(for: chosenCallee) {
                #expect(ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/collections/ListCollectionOps.kt")
            }
            let receiver = try #require(signature.receiverType)
            let iterableFQName = ["kotlin", "collections", "Iterable"].map(ctx.interner.intern)
            let iterableSymbol = try #require(sema.symbols.lookup(fqName: iterableFQName))
            guard case let .classType(receiverClass) = sema.types.kind(of: receiver) else {
                Issue.record("Expected the generic Iterable<Int> overload for an unsigned selector on a List<Int> receiver.")
                continue
            }
            #expect(receiverClass.classSymbol == iterableSymbol)
        }
    }
}

private func aggregateDiagnosticSummary(in ctx: CompilationContext) -> String {
    ctx.diagnostics.diagnostics
        .map { diagnostic in
            guard let range = diagnostic.primaryRange else {
                return "\(diagnostic.code): \(diagnostic.message)"
            }
            let position = ctx.sourceManager.lineColumn(of: range.start)
            return "\(ctx.sourceManager.path(of: range.start.file)):\(position.line):\(position.column): \(diagnostic.code): \(diagnostic.message)"
        }
        .joined(separator: "\n")
}
