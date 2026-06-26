@testable import CompilerCore
import XCTest

final class ReflectKTypeProjectionSyntheticTests: XCTestCase {
    func testKTypeProjectionPropertiesAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }
        let collectionsPackage = ["kotlin", "collections"].map { interner.intern($0) }

        let kTypeSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KType")]
        ))
        let kTypeProjectionSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KTypeProjection")]
        ))
        let kVarianceSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KVariance")]
        ))
        let listSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: collectionsPackage + [interner.intern("List")]
        ))

        XCTAssertEqual(sema.symbols.symbol(kTypeProjectionSymbol)?.kind, .class)
        XCTAssertTrue(sema.symbols.symbol(kTypeProjectionSymbol)?.flags.contains(.synthetic) == true)

        let nullableKVariance = sema.types.makeNullable(sema.types.make(.classType(ClassType(
            classSymbol: kVarianceSymbol,
            args: [],
            nullability: .nonNull
        ))))
        let nullableKType = sema.types.makeNullable(sema.types.make(.classType(ClassType(
            classSymbol: kTypeSymbol,
            args: [],
            nullability: .nonNull
        ))))

        let varianceSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KTypeProjection"), interner.intern("variance")]
        ))
        let typeSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KTypeProjection"), interner.intern("type")]
        ))
        XCTAssertEqual(sema.symbols.propertyType(for: varianceSymbol), nullableKVariance)
        XCTAssertEqual(sema.symbols.propertyType(for: typeSymbol), nullableKType)

        let projectionType = sema.types.make(.classType(ClassType(
            classSymbol: kTypeProjectionSymbol,
            args: [],
            nullability: .nonNull
        )))
        let listOfProjection = sema.types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(projectionType)],
            nullability: .nonNull
        )))
        let argumentsSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KType"), interner.intern("arguments")]
        ))
        XCTAssertEqual(sema.symbols.propertyType(for: argumentsSymbol), listOfProjection)
    }

    func testKTypeProjectionPropertiesResolveInSource() throws {
        let source = """
        import kotlin.reflect.KType
        import kotlin.reflect.KTypeProjection
        import kotlin.reflect.KVariance

        fun projectionVariance(projection: KTypeProjection): KVariance? = projection.variance
        fun projectionType(projection: KTypeProjection): KType? = projection.type
        fun typeArguments(type: KType): List<KTypeProjection> = type.arguments
        """

        _ = try makeSema(source: source)
    }
}
