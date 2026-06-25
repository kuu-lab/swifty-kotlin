@testable import CompilerCore
import XCTest

// STDLIB-CINTEROP-FN-039: kotlinx.cinterop.typeOf<T>() stub registration
final class CinteropTypeOfSyntheticTests: XCTestCase {
    func testCinteropTypeOfIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        let typeOfSymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: cinteropPkg + [interner.intern("typeOf")]).first,
            "Expected kotlinx.cinterop.typeOf to be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(typeOfSymbol))
        XCTAssertEqual(info.kind, .function)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertTrue(info.flags.contains(.inlineFunction))

        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: typeOfSymbol))
        XCTAssertTrue(sig.parameterTypes.isEmpty)
        XCTAssertEqual(sig.reifiedTypeParameterIndices, [0])
        XCTAssertNil(sig.receiverType)

        let reflectPkg = ["kotlin", "reflect"].map { interner.intern($0) }
        let kTypeSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: reflectPkg + [interner.intern("KType")])
        )
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: kTypeSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(sig.returnType, expectedReturnType)
    }

    func testCinteropTypeOfResolvesInSource() throws {
        let source = """
        import kotlinx.cinterop.typeOf
        import kotlin.reflect.KType

        fun getStringType(): KType = typeOf<String>()
        """
        let (_, _) = try makeSema(source: source)
    }
}
