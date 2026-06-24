@testable import CompilerCore
import XCTest

final class ReflectKMutableProperty1SyntheticTests: XCTestCase {
    func testKMutableProperty1SurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }
        let functionPackage = ["kotlin", "Function"].map { interner.intern($0) }

        let kProperty1Symbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty1")]
        ))
        let kMutablePropertySymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KMutableProperty")]
        ))
        let kMutableProperty1Symbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KMutableProperty1")]
        ))
        let function1Symbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: functionPackage + [interner.intern("Function1")]
        ))

        let kMutableProperty1Info = try XCTUnwrap(sema.symbols.symbol(kMutableProperty1Symbol))
        XCTAssertEqual(kMutableProperty1Info.kind, .interface)
        XCTAssertTrue(kMutableProperty1Info.flags.contains(.synthetic))

        let typeParams = sema.types.nominalTypeParameterSymbols(for: kMutableProperty1Symbol)
        XCTAssertEqual(typeParams.count, 2)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: kMutableProperty1Symbol), [.invariant, .invariant])

        let receiverTypeParam = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParams[0],
            nullability: .nonNull
        )))
        let valueType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParams[1],
            nullability: .nonNull
        )))
        let supertypes = sema.symbols.directSupertypes(for: kMutableProperty1Symbol)
        XCTAssertTrue(supertypes.contains(kProperty1Symbol))
        XCTAssertTrue(supertypes.contains(kMutablePropertySymbol))
        XCTAssertTrue(supertypes.contains(function1Symbol))
        XCTAssertEqual(
            sema.symbols.supertypeTypeArgs(for: kMutableProperty1Symbol, supertype: kProperty1Symbol),
            [.invariant(receiverTypeParam), .invariant(valueType)]
        )
        XCTAssertEqual(
            sema.symbols.supertypeTypeArgs(for: kMutableProperty1Symbol, supertype: kMutablePropertySymbol),
            [.invariant(valueType)]
        )
        XCTAssertEqual(
            sema.symbols.supertypeTypeArgs(for: kMutableProperty1Symbol, supertype: function1Symbol),
            [.out(valueType), .in(receiverTypeParam)]
        )

        let setSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KMutableProperty1"), interner.intern("set")]
        ))
        let setSignature = try XCTUnwrap(sema.symbols.functionSignature(for: setSymbol))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: kMutableProperty1Symbol,
            args: [.invariant(receiverTypeParam), .invariant(valueType)],
            nullability: .nonNull
        )))
        XCTAssertEqual(setSignature.receiverType, receiverType)
        XCTAssertEqual(setSignature.parameterTypes, [receiverTypeParam, valueType])
        XCTAssertEqual(setSignature.returnType, sema.types.unitType)
        XCTAssertEqual(setSignature.typeParameterSymbols, typeParams)
        XCTAssertEqual(setSignature.classTypeParameterCount, 2)
    }

    func testKMutableProperty1SetResolvesInSource() throws {
        let source = """
        import kotlin.reflect.KMutableProperty1

        fun <T, V> write(property: KMutableProperty1<T, V>, receiver: T, value: V) {
            property.set(receiver, value)
        }
        """

        _ = try makeSema(source: source)
    }
}
