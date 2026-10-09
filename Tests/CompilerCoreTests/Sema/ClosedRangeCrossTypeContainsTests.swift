#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ClosedRangeCrossTypeContainsTests {
    private let primitiveNames = ["Byte", "Short", "Int", "Long", "Float", "Double"]

    @Test
    func allThirtyUpstreamOverloadsAreSourceBacked() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected bundled source diagnostics: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let overloads = sema.symbols.lookupAll(
            fqName: ["kotlin", "ranges", "contains"].map(ctx.interner.intern)
        ).filter { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  let receiver = signature.receiverType,
                  case let .classType(receiverClass) = sema.types.kind(of: receiver)
            else {
                return false
            }
            return sema.symbols.symbol(receiverClass.classSymbol)?.fqName.map(ctx.interner.resolve)
                == ["kotlin", "ranges", "ClosedRange"]
                && signature.parameterTypes.count == 1
                && signature.typeParameterSymbols.isEmpty
        }

        #expect(overloads.count == 30)
        var pairs: Set<String> = []
        for overload in overloads {
            let signature = try #require(sema.symbols.functionSignature(for: overload))
            let receiver = try #require(signature.receiverType)
            guard case let .classType(receiverClass) = sema.types.kind(of: receiver),
                  case let .invariant(receiverElementType) = receiverClass.args.first,
                  case let .primitive(receiverPrimitive, .nonNull) = sema.types.kind(of: receiverElementType),
                  case let .primitive(argumentPrimitive, .nonNull) = sema.types.kind(of: signature.parameterTypes[0])
            else {
                Issue.record("Expected primitive ClosedRange contains overload")
                continue
            }

            #expect(signature.returnType == sema.types.booleanType)
            #expect(receiverClass.args.count == 1)
            #expect(receiverPrimitive != argumentPrimitive)
            #expect(sema.symbols.isSourceBackedSymbol(overload))
            let sourceFile = try #require(sema.symbols.sourceFileID(for: overload))
            #expect(ctx.sourceManager.path(of: sourceFile) == "__bundled_kotlin/ranges/ClosedRange.kt")
            pairs.insert("\(receiverPrimitive.kotlinName):\(argumentPrimitive.kotlinName)")
        }

        let expectedPairs = Set(primitiveNames.flatMap { receiver in
            primitiveNames.filter { $0 != receiver }.map { "\(receiver):\($0)" }
        })
        #expect(pairs == expectedPairs)
    }

    @Test
    func visibleCrossTypeCallsBindToSourceOverloads() throws {
        let ctx = makeContextFromSource("""
        fun byteShort(range: ClosedRange<Byte>, value: Short) = range.contains(value)
        fun byteInt(range: ClosedRange<Byte>, value: Int) = range.contains(value)
        fun byteLong(range: ClosedRange<Byte>, value: Long) = range.contains(value)
        fun shortByte(range: ClosedRange<Short>, value: Byte) = range.contains(value)
        fun shortInt(range: ClosedRange<Short>, value: Int) = range.contains(value)
        fun shortLong(range: ClosedRange<Short>, value: Long) = range.contains(value)
        fun intByte(range: ClosedRange<Int>, value: Byte) = range.contains(value)
        fun intShort(range: ClosedRange<Int>, value: Short) = range.contains(value)
        fun intLong(range: ClosedRange<Int>, value: Long) = range.contains(value)
        fun longByte(range: ClosedRange<Long>, value: Byte) = range.contains(value)
        fun longShort(range: ClosedRange<Long>, value: Short) = range.contains(value)
        fun longInt(range: ClosedRange<Long>, value: Int) = range.contains(value)
        fun floatDouble(range: ClosedRange<Float>, value: Double) = range.contains(value)
        fun doubleFloat(range: ClosedRange<Double>, value: Float) = range.contains(value)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected Sema diagnostics: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        var selectedPairs: Set<String> = []
        for index in ast.arena.exprs.indices {
            let id = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(id),
                  ctx.sourceManager.origin(of: range.start.file) == .user,
                  let binding = sema.bindings.callBinding(for: id),
                  let symbol = sema.symbols.symbol(binding.chosenCallee),
                  symbol.name == KnownCompilerNames(interner: ctx.interner).contains
            else { continue }

            let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
            let receiver = try #require(signature.receiverType)
            guard case let .classType(receiverClass) = sema.types.kind(of: receiver),
                  case let .invariant(receiverElementType) = receiverClass.args.first,
                  case let .primitive(receiverPrimitive, .nonNull) = sema.types.kind(of: receiverElementType),
                  case let .primitive(argumentPrimitive, .nonNull) = sema.types.kind(of: signature.parameterTypes[0])
            else {
                Issue.record("Expected a primitive ClosedRange source overload")
                continue
            }

            #expect(symbol.fqName.map(ctx.interner.resolve) == ["kotlin", "ranges", "contains"])
            #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
            selectedPairs.insert("\(receiverPrimitive.kotlinName):\(argumentPrimitive.kotlinName)")
        }

        let expectedPairs: Set<String> = [
            "Byte:Short", "Byte:Int", "Byte:Long",
            "Short:Byte", "Short:Int", "Short:Long",
            "Int:Byte", "Int:Short", "Int:Long",
            "Long:Byte", "Long:Short", "Long:Int",
            "Float:Double", "Double:Float",
        ]
        #expect(selectedPairs == expectedPairs)
    }
}
#endif
