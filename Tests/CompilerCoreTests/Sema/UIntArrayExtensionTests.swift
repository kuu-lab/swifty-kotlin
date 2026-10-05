#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite(.serialized)
struct UIntArrayExtensionTests {
    @Test
    func extensionsBindToBundledSourceWithExactReturnTypes() throws {
        let source = """
        fun copy(a: UIntArray): UIntArray = a.toUIntArray()
        fun convert(a: IntArray): UIntArray = a.toUIntArray()
        fun convert(a: Array<out UInt>): UIntArray = a.toUIntArray()
        fun convert(a: Collection<UInt>): UIntArray = a.toUIntArray()
        fun convert(a: List<UInt>): UIntArray = a.toUIntArray()
        fun indices(a: UIntArray): IntRange = a.indices
        fun lastIndex(a: UIntArray): Int = a.lastIndex
        fun sum(a: UIntArray): UInt = a.sum()
        fun max(a: UIntArray): UInt? = a.maxOrNull()
        fun min(a: UIntArray): UInt? = a.minOrNull()
        fun sorted(a: UIntArray): List<UInt> = a.sorted()
        fun element(a: UIntArray): UInt = a.elementAt(1)
        fun index(a: UIntArray): Int = a.indexOf(3u)
        fun visit(a: UIntArray) { a.forEachIndexed { i, v -> println(i); println(v) } }
        fun sumDouble(a: UIntArray): Double = a.sumOf { it.toDouble() }
        fun sumInt(a: UIntArray): Int = a.sumOf { it.toInt() }
        fun sumLong(a: UIntArray): Long = a.sumOf { it.toLong() }
        fun sumUInt(a: UIntArray): UInt = a.sumOf { it }
        fun sumULong(a: UIntArray): ULong = a.sumOf { it.toULong() }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let names: Set<String> = [
            "toUIntArray", "indices", "lastIndex", "sum", "maxOrNull", "minOrNull",
            "sorted", "elementAt", "indexOf", "forEachIndexed", "sumOf",
        ]
        var observed: [String: Int] = [:]
        var sumOfReturns: Set<TypeID> = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .memberCall(_, callee, _, _, range) = ast.arena.expr(exprID),
                  ctx.sourceManager.origin(of: range.start.file) == .user,
                  names.contains(ctx.interner.resolve(callee))
            else { continue }
            let name = ctx.interner.resolve(callee)
            let chosen = try #require(
                sema.bindings.callBinding(for: exprID)?.chosenCallee
                    ?? sema.bindings.identifierSymbol(for: exprID),
                "Missing source binding for \(name)"
            )
            #expect(sema.symbols.isSourceBackedSymbol(chosen))
            #expect(sema.symbols.externalLinkName(for: chosen) == nil)
            observed[name, default: 0] += 1
            if name == "sumOf" {
                let signature = try #require(sema.symbols.functionSignature(for: chosen))
                sumOfReturns.insert(signature.returnType)
                #expect(sema.symbols.symbol(chosen)?.flags.contains(.inlineFunction) == true)
            }
        }
        #expect(Set(observed.keys) == names)
        #expect(observed["toUIntArray"] == 5)
        #expect(observed["sumOf"] == 5)
        #expect(observed.values.reduce(0, +) == 19)
        #expect(sumOfReturns == Set([
            sema.types.doubleType, sema.types.intType, sema.types.longType,
            sema.types.uintType, sema.types.ulongType,
        ]))
    }

    @Test
    func unsignedArrayAverageRemainsUnsupported() throws {
        let ctx = makeContextFromSource("fun invalid(a: UIntArray) = a.average()")
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0024" })
    }
}
#endif
