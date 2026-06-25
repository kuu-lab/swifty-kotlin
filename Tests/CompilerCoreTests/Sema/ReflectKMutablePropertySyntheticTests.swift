@testable import CompilerCore
import XCTest

final class ReflectKMutablePropertySyntheticTests: XCTestCase {
    func testKMutablePropertySurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }

        let kPropertySymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty")]
        ))
        let kMutablePropertySymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KMutableProperty")]
        ))

        let kMutablePropertyInfo = try XCTUnwrap(sema.symbols.symbol(kMutablePropertySymbol))
        XCTAssertEqual(kMutablePropertyInfo.kind, .interface)
        XCTAssertTrue(kMutablePropertyInfo.flags.contains(.synthetic))

        let typeParams = sema.types.nominalTypeParameterSymbols(for: kMutablePropertySymbol)
        XCTAssertEqual(typeParams.count, 1)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: kMutablePropertySymbol), [.invariant])

        let valueType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParams[0],
            nullability: .nonNull
        )))
        XCTAssertTrue(sema.symbols.directSupertypes(for: kMutablePropertySymbol).contains(kPropertySymbol))
        XCTAssertEqual(
            sema.symbols.supertypeTypeArgs(for: kMutablePropertySymbol, supertype: kPropertySymbol),
            [.invariant(valueType)]
        )
    }

    func testKMutablePropertyTypeReferencesResolveInSource() throws {
        let source = """
        import kotlin.reflect.KMutableProperty

        fun <V> propertyName(property: KMutableProperty<V>): String = property.name
        """

        _ = try makeSema(source: source)
    }

    func testKMutablePropertySetterNestedTypeIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }

        let kMutablePropertySymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KMutableProperty")]
        ))
        let setterSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KMutableProperty"), interner.intern("Setter")]
        ))

        let setterInfo = try XCTUnwrap(sema.symbols.symbol(setterSymbol))
        XCTAssertEqual(setterInfo.kind, .interface)
        XCTAssertTrue(setterInfo.flags.contains(.synthetic))

        let typeParams = sema.types.nominalTypeParameterSymbols(for: setterSymbol)
        XCTAssertEqual(typeParams.count, 1)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: setterSymbol), [.invariant])

        // Setter should be a child of KMutableProperty.
        XCTAssertEqual(sema.symbols.parentSymbol(for: setterSymbol), kMutablePropertySymbol)
    }

    func testKMutablePropertySetterPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }

        let kMutablePropertySymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KMutableProperty")]
        ))
        let setterSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KMutableProperty"), interner.intern("Setter")]
        ))

        let setterPropSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KMutableProperty"), interner.intern("setter")]
        ))
        let setterPropInfo = try XCTUnwrap(sema.symbols.symbol(setterPropSymbol))
        XCTAssertEqual(setterPropInfo.kind, .property)
        XCTAssertTrue(setterPropInfo.flags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.parentSymbol(for: setterPropSymbol), kMutablePropertySymbol)

        let typeParams = sema.types.nominalTypeParameterSymbols(for: kMutablePropertySymbol)
        let valueType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParams[0],
            nullability: .nonNull
        )))
        let expectedSetterType = sema.types.make(.classType(ClassType(
            classSymbol: setterSymbol,
            args: [.invariant(valueType)],
            nullability: .nonNull
        )))
        XCTAssertEqual(sema.symbols.propertyType(for: setterPropSymbol), expectedSetterType)
    }

    func testKMutablePropertySetterAccessResolvesInSource() throws {
        let source = """
        import kotlin.reflect.KMutableProperty

        fun <V> getSetter(property: KMutableProperty<V>): KMutableProperty.Setter<V> = property.setter
        """

        _ = try makeSema(source: source)
    }
}
