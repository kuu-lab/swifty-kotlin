@testable import CompilerCore
import XCTest

final class ReflectCreateInstanceSyntheticTests: XCTestCase {
    func testCreateInstanceSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let functionFQName = ["kotlin", "reflect", "full", "createInstance"].map { interner.intern($0) }
        let functionSymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: functionFQName).first,
            "Expected kotlin.reflect.full.createInstance to be registered"
        )
        let symbol = try XCTUnwrap(sema.symbols.symbol(functionSymbol))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))

        XCTAssertEqual(symbol.kind, .function)
        XCTAssertEqual(symbol.visibility, .public)
        XCTAssertTrue(symbol.flags.contains(.synthetic))
        XCTAssertEqual(signature.parameterTypes, [])
        XCTAssertEqual(signature.typeParameterSymbols.count, 1)
        XCTAssertEqual(signature.typeParameterUpperBoundsList, [[sema.types.anyType]])

        let typeParam = try XCTUnwrap(signature.typeParameterSymbols.first)
        let typeParamType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParam,
            nullability: .nonNull
        )))
        let kClassSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: ["kotlin", "reflect", "KClass"].map { interner.intern($0) }
        ))
        XCTAssertEqual(signature.receiverType, sema.types.make(.classType(ClassType(
            classSymbol: kClassSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        ))))
        XCTAssertEqual(signature.returnType, typeParamType)
    }

    func testCreateInstanceResolvesInSource() throws {
        let source = """
        import kotlin.reflect.KClass
        import kotlin.reflect.full.createInstance

        class Box

        fun makeBox(): Box = Box::class.createInstance()

        fun <T : Any> make(kclass: KClass<T>): T =
            kclass.createInstance()
        """

        _ = try makeSema(source: source)
    }
}
