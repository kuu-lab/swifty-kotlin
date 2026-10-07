#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct LibraryMetadataLayoutValidationTests {
    @Test(arguments: [
        "fields=-1",
        "fields=1000001",
        "fields=9223372036854775808",
        "layoutWords=-1",
        "vtable=1000001",
        "itable=-1",
        "fieldOffsets=fixture.C.field@-1",
        "fieldOffsets=fixture.C.field@1000001",
        "vtableSlots=fixture.C.call#0#0@9223372036854775808",
        "itableSlots=fixture.I@-1",
    ])
    func rejectsOutOfRangeLayoutMetadata(layoutValue: String) throws {
        try withTemporaryFile(contents: "class _ fq=fixture.C schema=v1 \(layoutValue)\n") { path in
            let diagnostics = DiagnosticEngine()
            let records = DataFlowSemaPhase().parseLibraryMetadata(
                path: path,
                diagnostics: diagnostics,
                interner: StringInterner()
            )

            #expect(records == nil)
            #expect(diagnostics.diagnostics.contains { $0.code == "KSWIFTK-LIB-0003" })
        }
    }

    @Test func acceptsMaximumLayoutValuesForEmptyAndPopulatedLayouts() throws {
        let metadata = """
        class _ fq=fixture.Empty schema=v1 fields=1000000 layoutWords=1000000 vtable=1000000 itable=1000000
        class _ fq=fixture.Populated schema=v1 fields=1 fieldOffsets=fixture.Populated.field@1000000 vtableSlots=fixture.Populated.call#0#0@1000000 itableSlots=fixture.IFace@1000000
        """
        let interner = StringInterner()
        try withTemporaryFile(contents: metadata) { path in
            let diagnostics = DiagnosticEngine()
            let records = DataFlowSemaPhase().parseLibraryMetadata(
                path: path,
                diagnostics: diagnostics,
                interner: interner
            )

            #expect(records?.count == 2)
            #expect(diagnostics.diagnostics.isEmpty)
            #expect(records?.first?.fieldOffsets.isEmpty == true)
            #expect(records?.last?.fieldOffsets.first?.offset == 1_000_000)
            #expect(records?.last?.vtableSlots.first?.slot == 1_000_000)
            #expect(records?.last?.itableSlots.first?.slot == 1_000_000)

            let fixtureName = interner.intern("fixture")
            let emptyName = interner.intern("Empty")
            let populatedName = interner.intern("Populated")
            let fieldName = interner.intern("field")
            let callName = interner.intern("call")
            let interfaceName = interner.intern("IFace")
            let symbols = SymbolTable()
            let types = TypeSystem()
            types.symbolTable = symbols
            let emptyClass = symbols.define(
                kind: .class,
                name: emptyName,
                fqName: [fixtureName, emptyName],
                declSite: nil,
                visibility: .public
            )
            let populatedClass = symbols.define(
                kind: .class,
                name: populatedName,
                fqName: [fixtureName, populatedName],
                declSite: nil,
                visibility: .public
            )
            _ = symbols.define(
                kind: .field,
                name: fieldName,
                fqName: [fixtureName, populatedName, fieldName],
                declSite: nil,
                visibility: .public
            )
            let call = symbols.define(
                kind: .function,
                name: callName,
                fqName: [fixtureName, populatedName, callName],
                declSite: nil,
                visibility: .public
            )
            symbols.setFunctionSignature(
                FunctionSignature(parameterTypes: [], returnType: types.unitType, isSuspend: false),
                for: call
            )
            _ = symbols.define(
                kind: .interface,
                name: interfaceName,
                fqName: [fixtureName, interfaceName],
                declSite: nil,
                visibility: .public
            )

            let emptyRecord = try #require(records?.first)
            symbols.setNominalLayoutHint(
                NominalLayoutHint(
                    declaredFieldCount: emptyRecord.declaredFieldCount,
                    declaredInstanceSizeWords: emptyRecord.declaredInstanceSizeWords,
                    declaredVtableSize: emptyRecord.declaredVtableSize,
                    declaredItableSize: emptyRecord.declaredItableSize
                ),
                for: emptyClass
            )
            let populatedRecord = try #require(records?.last)
            DataFlowSemaPhase().applyImportedNominalLayout(
                record: populatedRecord,
                symbol: populatedClass,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                metadataPath: path,
                interner: interner
            )
            let populatedLayout = try #require(symbols.nominalLayout(for: populatedClass))
            #expect(populatedLayout.instanceSizeWords == 1_000_001)
            #expect(populatedLayout.vtableSize == 1_000_001)
            #expect(populatedLayout.itableSize == 1_000_001)

            DataFlowSemaPhase().synthesizeNominalLayouts(
                symbols: symbols,
                types: types,
                interner: interner,
                diagnostics: diagnostics
            )
            let emptyLayout = try #require(symbols.nominalLayout(for: emptyClass))
            #expect(emptyLayout.instanceFieldCount == 1_000_000)
            #expect(emptyLayout.instanceSizeWords == 1_000_002)
            #expect(emptyLayout.vtableSize == 1_000_000)
            #expect(emptyLayout.itableSize == 1_000_000)
            #expect(diagnostics.diagnostics.isEmpty)
        }
    }
}
#endif
