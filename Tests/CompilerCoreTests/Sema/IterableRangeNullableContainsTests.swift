#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct IterableRangeNullableContainsTests {
    @Test func nullableCallsAndOperatorsBindToSourceExtensions() throws {
        let ctx = makeContextFromSource("""
        fun check(range: IntRange, value: Int?): Boolean = range.contains(value)
        fun checkNull(range: IntRange): Boolean = range.contains(null)
        fun checkIn(range: IntRange, value: Int?): Boolean = value in range
        fun checkNotIn(range: IntRange, value: Int?): Boolean = value !in range
        fun checkLong(range: LongRange, value: Long?): Boolean = range.contains(value)
        fun checkChar(range: CharRange, value: Char?): Boolean = range.contains(value)
        fun checkUInt(range: UIntRange, value: UInt?): Boolean = range.contains(value)
        fun checkULong(range: ULongRange, value: ULong?): Boolean = range.contains(value)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        var bindings = 0
        for index in ast.arena.exprs.indices {
            let id = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(id),
                  ctx.sourceManager.origin(of: range.start.file) == .user,
                  let binding = sema.bindings.callBinding(for: id),
                  let symbol = sema.symbols.symbol(binding.chosenCallee),
                  ctx.interner.resolve(symbol.name) == "contains"
            else { continue }
            let signature = try #require(sema.symbols.functionSignature(for: symbol.id))
            #expect(signature.typeParameterSymbols.count == 2)
            #expect(sema.types.nullability(of: signature.parameterTypes[0]) == .nullable)
            #expect(sema.symbols.isSourceBackedSymbol(symbol.id))
            bindings += 1
        }
        #expect(bindings == 8)
    }

    @Test func allFourUpstreamDeclarationsArePresent() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let symbols = sema.symbols.lookupAll(fqName: ["kotlin", "ranges", "contains"].map(ctx.interner.intern))
        let nullableGenericOverloads = symbols.filter {
            guard let signature = sema.symbols.functionSignature(for: $0),
                  signature.typeParameterSymbols.count == 2,
                  let receiver = signature.receiverType,
                  case .typeParam = sema.types.kind(of: receiver),
                  signature.parameterTypes.count == 1
            else { return false }
            return sema.types.nullability(of: signature.parameterTypes[0]) == .nullable
        }
        #expect(nullableGenericOverloads.count == 4)
        #expect(nullableGenericOverloads.allSatisfy { sema.symbols.isSourceBackedSymbol($0) })
    }

    @Test func rangeOnlyReceiverAndWrongElementTypeAreRejected() throws {
        for source in [
            "fun bad(range: ClosedRange<Int>): Boolean = range.contains(null)",
            "fun bad(range: IntRange, value: String?): Boolean = range.contains(value)"
        ] {
            let ctx = makeContextFromSource(source)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
        }
    }
}
#endif
