#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KUU-622: generic Array.asIterable and Array.sumOf must be bundled Kotlin
/// source declarations, with the selector return type choosing the exact
/// Array.sumOf overload.
@Suite
struct ArrayIterableSumOfSourceMigrationTests {
    @Test
    func arrayIterableAndSumOfDeclarationsAreSourceBacked() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let arrayFQName = ["kotlin", "Array"].map(interner.intern)
        let arraySymbol = try #require(sema.symbols.lookup(fqName: arrayFQName))
        let collectionsFQName = ["kotlin", "collections"].map(interner.intern)

        let symbolsFor: (String, String) -> [SymbolID] = { name, sourcePath in
            sema.symbols.lookupAll(fqName: collectionsFQName + [interner.intern(name)]).filter { id in
                guard let symbol = sema.symbols.symbol(id),
                      symbol.kind == .function,
                      symbol.visibility == .public,
                      !symbol.flags.contains(.synthetic),
                      let fileID = sema.symbols.sourceFileID(for: id),
                      ctx.sourceManager.path(of: fileID) == sourcePath,
                      let signature = sema.symbols.functionSignature(for: id),
                      let receiver = signature.receiverType,
                      case let .classType(receiverClass) = sema.types.kind(of: sema.types.makeNonNullable(receiver))
                else {
                    return false
                }
                return receiverClass.classSymbol == arraySymbol
            }
        }

        let asIterableSymbols = symbolsFor(
            "asIterable",
            "__bundled_kotlin/collections/ArrayConversions.kt"
        )
        #expect(asIterableSymbols.count == 1)
        #expect(asIterableSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })
        #expect(asIterableSymbols.allSatisfy { sema.symbols.functionSignature(for: $0)?.parameterTypes.isEmpty == true })

        let sumOfSymbols = symbolsFor(
            "sumOf",
            "__bundled_kotlin/collections/ArrayAggregateHOF.kt"
        )
        #expect(sumOfSymbols.count == 5, "Expected exactly 5 Array.sumOf overloads, got (sumOfSymbols.count)")
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
    func arrayIterableAndSumOfCallsBindToMatchingSourceOverloads() throws {
        let source = """
        fun asIterableCall(values: Array<String>): Iterable<String> = values.asIterable()
        fun sumOfDouble(values: Array<String>): Double = values.sumOf { it.length.toDouble() }
        fun sumOfInt(values: Array<String>): Int = values.sumOf { it.length }
        fun sumOfLong(values: Array<String>): Long = values.sumOf { it.length.toLong() }
        fun sumOfUInt(values: Array<String>): UInt = values.sumOf { it.length.toUInt() }
        fun sumOfULong(values: Array<String>): ULong = values.sumOf { it.length.toULong() }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics.map { $0.message }.joined(separator: " | ")
        #expect(
            !ctx.diagnostics.hasError,
            Comment(rawValue: "Unexpected diagnostics: " + diagnostics)
        )
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let userFileID = try #require(ctx.sourceManager.fileIDs().first {
            ctx.sourceManager.origin(of: $0) == .user
        })
        var asIterableCalls = 0
        var sumOfReturns: Set<TypeID> = []

        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .memberCall(_, callee, _, _, range) = ast.arena.expr(exprID),
                  ["asIterable", "sumOf"].contains(ctx.interner.resolve(callee)),
                  range.start.file == userFileID
            else {
                continue
            }
            let name = ctx.interner.resolve(callee)
            let binding = try #require(sema.bindings.callBinding(for: exprID), "Missing binding for (name)")
            let chosen = try #require(sema.symbols.symbol(binding.chosenCallee))
            let fileID = try #require(sema.symbols.sourceFileID(for: binding.chosenCallee))
            #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
            #expect(sema.symbols.externalLinkName(for: binding.chosenCallee) == nil)
            if name == "asIterable" {
                #expect(ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/collections/ArrayConversions.kt")
                #expect(chosen.name == ctx.interner.intern("asIterable"))
                asIterableCalls += 1
            } else {
                #expect(ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/collections/ArrayAggregateHOF.kt")
                if let returnType = sema.symbols.functionSignature(for: binding.chosenCallee)?.returnType {
                    sumOfReturns.insert(returnType)
                }
            }
        }

        #expect(asIterableCalls == 1)
        #expect(sumOfReturns == Set([
            sema.types.doubleType, sema.types.intType, sema.types.longType,
            sema.types.uintType, sema.types.ulongType,
        ]))
    }
}
#endif
