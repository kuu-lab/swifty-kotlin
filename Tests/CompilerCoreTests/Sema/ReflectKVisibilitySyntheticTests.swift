@testable import CompilerCore
import XCTest

final class ReflectKVisibilitySyntheticTests: XCTestCase {
    func testKVisibilityEnumEntriesAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }
        let enumFQName = reflectPackage + [interner.intern("KVisibility")]
        let enumSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: enumFQName),
            "Expected kotlin.reflect.KVisibility to be registered"
        )

        XCTAssertEqual(sema.symbols.symbol(enumSymbol)?.kind, .enumClass)
        XCTAssertTrue(sema.symbols.symbol(enumSymbol)?.flags.contains(.synthetic) == true)

        let enumType = sema.types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))
        for entry in ["PUBLIC", "PROTECTED", "INTERNAL", "PRIVATE"] {
            let entrySymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: enumFQName + [interner.intern(entry)]),
                "Expected KVisibility.\(entry) to be registered"
            )
            XCTAssertEqual(sema.symbols.parentSymbol(for: entrySymbol), enumSymbol)
            XCTAssertEqual(sema.symbols.propertyType(for: entrySymbol), enumType)
        }
    }

    func testKVisibilityEntriesResolveInSource() throws {
        let source = """
        import kotlin.reflect.KVisibility

        fun visibility(): KVisibility = KVisibility.PUBLIC

        fun isPrivate(visibility: KVisibility): Boolean =
            visibility == KVisibility.PRIVATE
        """

        _ = try makeSema(source: source)
    }
}
