#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct BundledSyntheticOverlapDiagnosticTests {
    @Test
    func testDiagnosticRegistered() {
        let descriptor = DiagnosticRegistry.lookup("KSWIFTK-SEMA-0102")
        #expect(descriptor != nil)
        #expect(descriptor?.defaultSeverity == .warning)
    }

    @Test
    func testWarnsWhenSyntheticOverlapsBundledIndex() {
        let symbols = SymbolTable()
        let types = TypeSystem()
        types.symbolTable = symbols
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()

        let listName = interner.intern("List")
        let collectionsPkg: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
        ]
        let listFQName = collectionsPkg + [listName]
        let listSymbol = symbols.define(
            kind: .interface,
            name: listName,
            fqName: listFQName,
            declSite: nil,
            visibility: .public,
            flags: []
        )

        let countName = interner.intern("count")
        let countFQName = listFQName + [countName]
        let bundledCount = symbols.define(
            kind: .function,
            name: countName,
            fqName: countFQName,
            declSite: nil,
            visibility: .public,
            flags: []
        )
        symbols.setParentSymbol(listSymbol, for: bundledCount)
        let elementType = types.anyType
        let receiverType = types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
        let predicateType = types.make(.functionType(FunctionType(
            params: [elementType],
            returnType: types.booleanType,
            isSuspend: false,
            nullability: .nonNull
        )))
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [predicateType],
                returnType: types.intType
            ),
            for: bundledCount
        )

        var bundledIndex = BundledDeclarationIndex.empty
        bundledIndex.insert(
            BundledMemberKey(
                ownerFQName: listFQName,
                name: countName,
                arity: 1
            )
        )

        let syntheticCount = symbols.define(
            kind: .function,
            name: countName,
            fqName: countFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(listSymbol, for: syntheticCount)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [predicateType],
                returnType: types.intType
            ),
            for: syntheticCount
        )

        bundledIndex.warnSyntheticOverlaps(
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: interner
        )

        assertHasDiagnostic("KSWIFTK-SEMA-0102", in: makeContext(diagnostics: diagnostics))
    }

    @Test
    func testNoOverlapWarningAfterFullSemaWithStdlib() throws {
        let source = """
        fun main() {
            val xs = listOf(1, 2, 3)
            println(xs.count())
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let overlapDiags = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0102" }
        #expect(overlapDiags.isEmpty, "Unexpected overlap warnings: \(overlapDiags.map(\.message))")
    }

    private func makeContext(diagnostics: DiagnosticEngine) -> CompilationContext {
        makeCompilationContext(inputs: ["/tmp/test.kt"], diagnostics: diagnostics)
    }
}
#endif
