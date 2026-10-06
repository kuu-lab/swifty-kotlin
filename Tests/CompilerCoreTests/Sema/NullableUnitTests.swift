@testable import CompilerCore
import Foundation
import Testing

@Suite
struct NullableUnitTests {
    @Test
    func typeSystemPreservesNullableUnit() {
        let types = TypeSystem()
        let nullable = types.makeNullable(types.unitType)
        #expect(nullable != types.unitType)
        #expect(types.kind(of: nullable) == .nullableUnit)
        #expect(types.nullability(of: nullable) == .nullable)
        #expect(!types.isDefinitelyNonNull(nullable))
        #expect(types.makeNonNullable(nullable) == types.unitType)
        #expect(types.makeNullable(nullable) == nullable)
        #expect(types.isSubtype(types.nullableNothingType, nullable))
        #expect(types.isSubtype(types.unitType, nullable))
        #expect(!types.isSubtype(nullable, types.unitType))
        #expect(!types.isSubtype(nullable, types.anyType))
        #expect(types.isSubtype(nullable, types.nullableAnyType))
        #expect(types.lub([types.unitType, types.nullableNothingType]) == nullable)
        #expect(types.lub([types.unitType, nullable]) == nullable)
        #expect(types.renderType(nullable) == "Unit?")
        let symbol = SymbolID(rawValue: 42)
        types.unitClassSymbol = symbol
        let nominal = types.make(.classType(ClassType(classSymbol: symbol)))
        let nullableNominal = types.makeNullable(nominal)
        #expect(types.isSubtype(nominal, types.unitType))
        #expect(types.isSubtype(types.unitType, nullableNominal))
        #expect(types.isSubtype(nullableNominal, nullable))
        #expect(types.isSubtype(nullable, nullableNominal))
        #expect(!types.isSubtype(nullableNominal, types.unitType))
    }

    @Test
    func nullableUnitMetadataRoundTrips() throws {
        let types = TypeSystem()
        let symbols = SymbolTable()
        let encoded = NameMangler().encodeType(
            types.makeNullable(types.unitType), symbols: symbols, types: types, nameResolver: nil
        )
        #expect(encoded == "Q<U>")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kklib")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try """
        {"formatVersion": 1, "moduleName": "NullableUnit", "metadata": "metadata.bin"}
        """.write(to: directory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try """
        symbols=1
        function _ fq=nullableunit.empty schema=v1 arity=0 sig=F0<\(encoded)> link=nullable_unit_empty
        """.write(to: directory.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump, searchPaths: [directory.path])
            let diagnostics = DiagnosticEngine()
            let interner = StringInterner()
            _ = DataFlowSemaPhase().loadImportedLibrarySymbols(
                options: ctx.options, symbols: symbols, types: types, diagnostics: diagnostics,
                interner: interner, importedInlineFunctions: ImportedInlineFunctionStore()
            )
            let function = try #require(symbols.lookup(fqName: ["nullableunit", "empty"].map(interner.intern)))
            #expect(symbols.functionSignature(for: function)?.returnType == types.makeNullable(types.unitType))
            #expect(!diagnostics.hasError)
        }
    }

    @Test
    func nullableUnitInitializersAndReturnsAreAccepted() throws {
        let ctx = makeContextFromSource("""
        fun empty(): Unit? = null
        fun present(): Unit? = Unit
        fun main() {
            var unit: Unit? = null
            unit = Unit
            unit = empty()
            val widened: Any? = unit
            val text: String? = unit?.toString()
            val value: Unit = unit ?: Unit
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func nullableUnitExpectActualSignaturesMatch() throws {
        let ctx = makeContextFromSources([
            "expect fun empty(): Unit?",
            "actual fun empty(): Unit? = null"
        ])
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "fun main() { val unit: Unit = null }",
        "fun main() { val nullable: Unit? = null; val unit: Unit = nullable }",
        "fun main() { val unit: Unit? = 1 }",
        "lateinit var unit: Unit?"
    ])
    func invalidUnitInitializersAreRejected(source: String) {
        let ctx = makeContextFromSource(source)
        try? runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }
}
