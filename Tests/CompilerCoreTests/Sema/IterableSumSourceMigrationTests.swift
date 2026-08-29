#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-994: `Iterable.sum` and `Iterable.sumOf` must be real bundled Kotlin
/// source declarations, with the selector return type choosing the exact
/// `sumOf` overload.
@Suite
struct IterableSumSourceMigrationTests {
    private let sourcePath = "__bundled_kotlin/collections/ListCollectionOps.kt"

    @Test
    func iterableSumFamilyDeclarationsAreSourceBacked() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let iterableFQName = ["kotlin", "collections", "Iterable"].map(interner.intern)
        let iterableSymbol = try #require(sema.symbols.lookup(fqName: iterableFQName))
        let collectionsFQName = ["kotlin", "collections"].map(interner.intern)

        let symbolsFor: (String) -> [SymbolID] = { name in
            sema.symbols.lookupAll(fqName: collectionsFQName + [interner.intern(name)]).filter { id in
                guard let symbol = sema.symbols.symbol(id),
                      symbol.kind == .function,
                      symbol.visibility == .public,
                      !symbol.flags.contains(.synthetic),
                      let fileID = sema.symbols.sourceFileID(for: id),
                      let signature = sema.symbols.functionSignature(for: id),
                      let receiver = signature.receiverType,
                      case let .classType(receiverClass) = sema.types.kind(of: receiver)
                else {
                    return false
                }
                return receiverClass.classSymbol == iterableSymbol
                    && ctx.sourceManager.path(of: fileID) == sourcePath
            }
        }

        let sumSymbols = symbolsFor("sum")
        #expect(sumSymbols.count == 10, "Expected exactly 10 Iterable.sum overloads, got \(sumSymbols.count)")
        let sumElementTypes = Set(sumSymbols.compactMap { id -> TypeID? in
            guard let receiver = sema.symbols.functionSignature(for: id)?.receiverType,
                  case let .classType(receiverClass) = sema.types.kind(of: receiver),
                  let firstArg = receiverClass.args.first
            else {
                return nil
            }
            return switch firstArg {
            case let .invariant(type), let .out(type), let .in(type): type
            case .star: nil
            }
        })
        #expect(sumElementTypes == Set([
            sema.types.byteType, sema.types.doubleType, sema.types.floatType,
            sema.types.intType, sema.types.longType, sema.types.shortType,
            sema.types.ubyteType, sema.types.uintType, sema.types.ulongType,
            sema.types.ushortType,
        ]))
        #expect(Set(sumSymbols.compactMap { sema.symbols.functionSignature(for: $0)?.returnType }) == Set([
            sema.types.intType, sema.types.doubleType, sema.types.floatType,
            sema.types.longType, sema.types.uintType, sema.types.ulongType,
        ]))

        let sumOfSymbols = symbolsFor("sumOf")
        #expect(sumOfSymbols.count == 5, "Expected exactly 5 Iterable.sumOf overloads, got \(sumOfSymbols.count)")
        #expect(Set(sumOfSymbols.compactMap { sema.symbols.functionSignature(for: $0)?.returnType }) == Set([
            sema.types.doubleType, sema.types.intType, sema.types.longType,
            sema.types.uintType, sema.types.ulongType,
        ]))
        #expect(sumOfSymbols.allSatisfy { sema.symbols.symbol($0)?.flags.contains(.inlineFunction) == true })
        #expect(sumOfSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })
        let annotatedReturns = Set(sumOfSymbols.filter { id in
            sema.symbols.annotations(for: id).contains {
                KnownCompilerAnnotation.overloadResolutionByLambdaReturnType.matches($0.annotationFQName)
            }
        }.compactMap { sema.symbols.functionSignature(for: $0)?.returnType })
        #expect(annotatedReturns == Set([sema.types.doubleType, sema.types.longType, sema.types.ulongType]))
    }

    @Test
    func iterableSumCallsBindToMatchingSourceOverloads() throws {
        let source = """
        fun byteSum(values: Iterable<Byte>): Int = values.sum()
        fun shortSum(values: Iterable<Short>): Int = values.sum()
        fun intSum(values: Iterable<Int>): Int = values.sum()
        fun longSum(values: Iterable<Long>): Long = values.sum()
        fun floatSum(values: Iterable<Float>): Float = values.sum()
        fun doubleSum(values: Iterable<Double>): Double = values.sum()
        fun ubyteSum(values: Iterable<UByte>): UInt = values.sum()
        fun ushortSum(values: Iterable<UShort>): UInt = values.sum()
        fun uintSum(values: Iterable<UInt>): UInt = values.sum()
        fun ulongSum(values: Iterable<ULong>): ULong = values.sum()
        fun sumOfDouble(values: Iterable<String>): Double = values.sumOf { it.length.toDouble() }
        fun sumOfInt(values: Iterable<String>): Int = values.sumOf { it.length }
        fun sumOfLong(values: Iterable<String>): Long = values.sumOf { it.length.toLong() }
        fun sumOfUInt(values: Iterable<String>): UInt = values.sumOf { it.length.toUInt() }
        fun sumOfULong(values: Iterable<String>): ULong = values.sumOf { it.length.toULong() }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            Comment(rawValue: diagnosticSummary(in: ctx))
        )
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let userFileID = try #require(ctx.sourceManager.fileIDs().first { ctx.sourceManager.origin(of: $0) == .user })
        let expectedReturns: [String: TypeID] = [
            "byteSum": sema.types.intType, "shortSum": sema.types.intType,
            "intSum": sema.types.intType, "longSum": sema.types.longType,
            "floatSum": sema.types.floatType, "doubleSum": sema.types.doubleType,
            "ubyteSum": sema.types.uintType, "ushortSum": sema.types.uintType,
            "uintSum": sema.types.uintType, "ulongSum": sema.types.ulongType,
            "sumOfDouble": sema.types.doubleType, "sumOfInt": sema.types.intType,
            "sumOfLong": sema.types.longType, "sumOfUInt": sema.types.uintType,
            "sumOfULong": sema.types.ulongType,
        ]

        var calls: [(name: String, id: ExprID)] = []
        for index in ast.arena.exprs.indices {
            let id = ExprID(rawValue: Int32(index))
            guard case let .memberCall(receiverID, callee, _, _, _) = ast.arena.expr(id),
                  ["sum", "sumOf"].contains(ctx.interner.resolve(callee)),
                  let range = ast.arena.exprRange(id),
                  range.start.file == userFileID,
                  let enclosingName = sourceFunctionName(
                      at: ctx.sourceManager.lineColumn(of: range.start).line,
                      source: source
                  )
            else {
                continue
            }
            let binding = try #require(sema.bindings.callBinding(for: id), "Missing call binding for \(enclosingName)")
            let chosen = try #require(sema.symbols.symbol(binding.chosenCallee))
            let fileID = try #require(sema.symbols.sourceFileID(for: binding.chosenCallee))
            #expect(ctx.sourceManager.path(of: fileID) == sourcePath)
            #expect(sema.symbols.externalLinkName(for: binding.chosenCallee) == nil)
            let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
            #expect(signature.returnType == expectedReturns[enclosingName])
            #expect(chosen.visibility == .public)
            if ctx.interner.resolve(callee) == "sumOf" {
                #expect(signature.parameterTypes.count == 1)
                #expect(binding.substitutedTypeArguments.count == 1)
                #expect(binding.substitutedTypeArguments.first == sema.types.stringType)
            } else {
                #expect(signature.parameterTypes.isEmpty)
                let actualReceiver = try #require(sema.bindings.exprTypes[receiverID])
                let actualElement: TypeID? = if case let .classType(classType) = sema.types.kind(of: actualReceiver),
                                                  let firstArg = classType.args.first
                {
                    switch firstArg {
                    case let .invariant(type), let .out(type), let .in(type): type
                    case .star: nil
                    }
                } else {
                    nil
                }
                let signatureElement: TypeID? = if let receiver = signature.receiverType,
                                                    case let .classType(classType) = sema.types.kind(of: receiver),
                                                    let firstArg = classType.args.first
                {
                    switch firstArg {
                    case let .invariant(type), let .out(type), let .in(type): type
                    case .star: nil
                    }
                } else {
                    nil
                }
                #expect(actualElement == signatureElement)
            }
            _ = receiverID
            calls.append((enclosingName, id))
        }
        #expect(calls.count == expectedReturns.count, "Expected 15 bound calls, got \(calls.count)")
    }

    @Test
    func concreteListSumKeepsListSourceBinding() throws {
        let source = """
        fun main() {
            println(listOf(1, 2, 3, 4).sum())
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: ctx)))
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let userFileID = try #require(ctx.sourceManager.fileIDs().first {
            ctx.sourceManager.origin(of: $0) == .user
        })
        let sumCallID = try #require(ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard case let .memberCall(_, callee, _, _, _) = ast.arena.expr(id),
                  ctx.interner.resolve(callee) == "sum",
                  let range = ast.arena.exprRange(id),
                  range.start.file == userFileID
            else {
                return nil
            }
            return id
        }.first)
        let binding = try #require(sema.bindings.callBinding(for: sumCallID))
        let chosen = try #require(sema.symbols.symbol(binding.chosenCallee))
        let fileID = try #require(sema.symbols.sourceFileID(for: binding.chosenCallee))
        #expect(ctx.sourceManager.path(of: fileID) == sourcePath)
        #expect(ctx.interner.resolve(chosen.name) == "sum")
        #expect(sema.symbols.externalLinkName(for: binding.chosenCallee) == nil)
        let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
        #expect(signature.returnType == sema.types.intType)
        #expect(signature.parameterTypes.isEmpty)
        let receiver = try #require(signature.receiverType)
        let listFQName = ["kotlin", "collections", "List"].map(ctx.interner.intern)
        let listSymbol = try #require(sema.symbols.lookup(fqName: listFQName))
        guard case let .classType(receiverClass) = sema.types.kind(of: receiver) else {
            Issue.record("Expected List receiver type for concrete List.sum binding.")
            return
        }
        #expect(receiverClass.classSymbol == listSymbol)
    }

    /// KSP-994 regression: `Deferred<T>.await()` can't recover `T` statically
    /// (Deferred has no class-level type parameter), so piping a
    /// `List<Deferred<Int>>` through `.map { it.await() }` erases the mapped
    /// list's element type to `Any`. A `List<Any>` receiver reaches the exact
    /// same "concrete list, unknown element type" state without needing the
    /// coroutine runtime, so exercise it directly here; the end-to-end
    /// scenario is covered by `Scripts/diff_cases/coroutine_deferred.kt`.
    /// Before the fix, `sum()` on this receiver never bound at all, leaking
    /// an unresolved `sum` callee through to the linker (KSWIFTK-LINK-0001).
    @Test
    func erasedListElementTypeSumFallsBackToIntBinding() throws {
        let source = """
        fun main() {
            val results: List<Any> = listOf(1, 2, 3, 4)
            println(results.sum())
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: ctx)))
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let userFileID = try #require(ctx.sourceManager.fileIDs().first {
            ctx.sourceManager.origin(of: $0) == .user
        })
        let sumCallID = try #require(ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard case let .memberCall(_, callee, _, _, _) = ast.arena.expr(id),
                  ctx.interner.resolve(callee) == "sum",
                  let range = ast.arena.exprRange(id),
                  range.start.file == userFileID
            else {
                return nil
            }
            return id
        }.first)
        let binding = try #require(
            sema.bindings.callBinding(for: sumCallID),
            "sum() on an erased List<Any> receiver must still bind to a real callee"
        )
        let chosen = try #require(sema.symbols.symbol(binding.chosenCallee))
        #expect(ctx.interner.resolve(chosen.name) == "sum")
        let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
        #expect(signature.returnType == sema.types.intType)
        let receiver = try #require(signature.receiverType)
        let listFQName = ["kotlin", "collections", "List"].map(ctx.interner.intern)
        let listSymbol = try #require(sema.symbols.lookup(fqName: listFQName))
        guard case let .classType(receiverClass) = sema.types.kind(of: receiver) else {
            Issue.record("Expected List receiver type for the fallback Int binding.")
            return
        }
        #expect(receiverClass.classSymbol == listSymbol)
    }
}

private func sourceFunctionName(at line: Int, source: String) -> String? {
    let names = [
        "byteSum", "shortSum", "intSum", "longSum", "floatSum", "doubleSum",
        "ubyteSum", "ushortSum", "uintSum", "ulongSum", "sumOfDouble", "sumOfInt",
        "sumOfLong", "sumOfUInt", "sumOfULong",
    ]
    let sourceLine = source.split(separator: "\n", omittingEmptySubsequences: false)[safe: line - 1].map(String.init) ?? ""
    return names.first { sourceLine.contains("fun \($0)(") }
}

private func diagnosticSummary(in ctx: CompilationContext) -> String {
    ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: "\n")
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
#endif
