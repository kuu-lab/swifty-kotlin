@testable import CompilerCore
import Testing

@Suite
struct SequenceInterfaceSyntheticTests {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(!ctx.diagnostics.hasError, Comment(rawValue: "Expected Sequence interface surface to resolve cleanly, got: \(diagnostics)"))
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testSequenceInterfaceSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sequencePackage = ["kotlin", "sequences"].map { interner.intern($0) }
        let collectionsPackage = ["kotlin", "collections"].map { interner.intern($0) }

        let sequenceSymbol = try #require(sema.symbols.lookup(
            fqName: sequencePackage + [interner.intern("Sequence")]
        ))
        let iteratorSymbol = try #require(sema.symbols.lookup(
            fqName: collectionsPackage + [interner.intern("Iterator")]
        ))
        let sequenceInfo = try #require(sema.symbols.symbol(sequenceSymbol))
        #expect(sequenceInfo.kind == .interface)
        #expect(sequenceInfo.flags.contains(.synthetic))

        let typeParams = sema.types.nominalTypeParameterSymbols(for: sequenceSymbol)
        #expect(typeParams.count == 1)
        #expect(sema.types.nominalTypeParameterVariances(for: sequenceSymbol) == [.out])

        let elementType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParams[0],
            nullability: .nonNull
        )))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
        let iteratorType = sema.types.make(.classType(ClassType(
            classSymbol: iteratorSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))

        let iteratorMember = try #require(sema.symbols.lookup(
            fqName: sequencePackage + [interner.intern("Sequence"), interner.intern("iterator")]
        ))
        #expect(sema.symbols.symbol(iteratorMember)?.flags.contains(.operatorFunction) == true)
        let signature = try #require(sema.symbols.functionSignature(for: iteratorMember))
        #expect(signature.receiverType == receiverType)
        #expect(signature.parameterTypes == [])
        #expect(signature.returnType == iteratorType)
        #expect(signature.typeParameterSymbols == typeParams)
        #expect(signature.classTypeParameterCount == 1)
    }

    @Test func testSequenceIteratorResolvesInSource() throws {
        let source = """
        import kotlin.collections.Iterator
        import kotlin.sequences.Sequence

        fun <T> iteratorOf(values: Sequence<T>): Iterator<T> =
            values.iterator()
        """

        _ = try makeSema(source: source)
    }
}
