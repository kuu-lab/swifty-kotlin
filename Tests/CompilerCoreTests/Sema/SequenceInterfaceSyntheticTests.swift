@testable import CompilerCore
import XCTest

final class SequenceInterfaceSyntheticTests: XCTestCase {
    func testSequenceInterfaceSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sequencePackage = ["kotlin", "sequences"].map { interner.intern($0) }
        let collectionsPackage = ["kotlin", "collections"].map { interner.intern($0) }

        let sequenceSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: sequencePackage + [interner.intern("Sequence")]
        ))
        let iteratorSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: collectionsPackage + [interner.intern("Iterator")]
        ))
        let sequenceInfo = try XCTUnwrap(sema.symbols.symbol(sequenceSymbol))
        XCTAssertEqual(sequenceInfo.kind, .interface)
        XCTAssertTrue(sequenceInfo.flags.contains(.synthetic))

        let typeParams = sema.types.nominalTypeParameterSymbols(for: sequenceSymbol)
        XCTAssertEqual(typeParams.count, 1)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: sequenceSymbol), [.out])

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

        let iteratorMember = try XCTUnwrap(sema.symbols.lookup(
            fqName: sequencePackage + [interner.intern("Sequence"), interner.intern("iterator")]
        ))
        XCTAssertTrue(sema.symbols.symbol(iteratorMember)?.flags.contains(.operatorFunction) == true)
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: iteratorMember))
        XCTAssertEqual(signature.receiverType, receiverType)
        XCTAssertEqual(signature.parameterTypes, [])
        XCTAssertEqual(signature.returnType, iteratorType)
        XCTAssertEqual(signature.typeParameterSymbols, typeParams)
        XCTAssertEqual(signature.classTypeParameterCount, 1)
    }

    func testSequenceIteratorResolvesInSource() throws {
        let source = """
        import kotlin.collections.Iterator
        import kotlin.sequences.Sequence

        fun <T> iteratorOf(values: Sequence<T>): Iterator<T> =
            values.iterator()
        """

        _ = try makeSema(source: source)
    }
}
