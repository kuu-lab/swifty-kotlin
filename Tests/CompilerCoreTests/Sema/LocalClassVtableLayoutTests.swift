#if canImport(Testing)
import CompilerCore
import Testing

@Suite
struct LocalClassVtableLayoutTests {
    /// A local `open`/`abstract` class must give its own methods vtable slots
    /// and grow `vtableSize`, and a local subclass' `override` must reuse the
    /// inherited slot. Without this, calls through a base-typed reference are
    /// lowered as direct calls to the base implementation.
    @Test
    func localOpenAndAbstractClassesGetVtableSlots() throws {
        let source = """
        package localvt

        fun main() {
            open class LBase(val b: Int) { open fun d() = "LBase$b"; fun plain() = 1 }
            class LDer : LBase(9) { override fun d() = "LDer" }
            abstract class Shape { abstract fun area(): Int }
            class Sq(val s: Int) : Shape() { override fun area() = s * s }
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let interner = ctx.interner

            func localClass(_ name: String) throws -> SymbolID {
                try #require(symbols.symbols(ofKind: .class).first {
                    symbols.symbol($0).map { interner.resolve($0.name) == name } ?? false
                })
            }
            func method(_ name: String, in owner: SymbolID) throws -> SymbolID {
                let ownerFQName = try #require(symbols.symbol(owner)).fqName
                return try #require(symbols.children(ofFQName: ownerFQName).first {
                    guard let sym = symbols.symbol($0) else { return false }
                    return sym.kind == .function && interner.resolve(sym.name) == name
                })
            }

            let base = try localClass("LBase")
            let derived = try localClass("LDer")
            let baseLayout = try #require(symbols.nominalLayout(for: base))
            let derivedLayout = try #require(symbols.nominalLayout(for: derived))
            let baseD = try method("d", in: base)
            let derivedD = try method("d", in: derived)
            let basePlain = try method("plain", in: base)

            let baseSlot = try #require(baseLayout.vtableSlots[baseD])
            #expect(baseLayout.vtableSlots[basePlain] != nil)
            #expect(baseLayout.vtableSlots[basePlain] != baseSlot)
            #expect(baseLayout.vtableSize >= 2)
            #expect(derivedLayout.vtableSlots[derivedD] == baseSlot)
            #expect(derivedLayout.vtableSize >= baseLayout.vtableSize)

            let shape = try localClass("Shape")
            let sq = try localClass("Sq")
            let shapeArea = try method("area", in: shape)
            let sqArea = try method("area", in: sq)
            let areaSlot = try #require(symbols.nominalLayout(for: shape)?.vtableSlots[shapeArea])
            #expect(symbols.nominalLayout(for: sq)?.vtableSlots[sqArea] == areaSlot)
        }
    }
}
#endif
