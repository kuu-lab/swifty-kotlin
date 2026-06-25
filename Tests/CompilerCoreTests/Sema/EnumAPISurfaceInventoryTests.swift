@testable import CompilerCore
import XCTest

final class EnumAPISurfaceInventoryTests: XCTestCase {
    func testEnumEntriesInterfaceIsRegisteredUnderKotlinEnums() throws {
        let (sema, interner) = try makeSema()
        let enumEntriesSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("enums"),
            interner.intern("EnumEntries"),
        ]))
        XCTAssertEqual(sema.symbols.symbol(enumEntriesSymbol)?.kind, .interface)
        XCTAssertNil(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("EnumEntries"),
        ]))
    }

    func testEnumEntriesFunctionReturnsKotlinEnumsEnumEntries() throws {
        let (sema, interner) = try makeSema()
        let enumEntriesSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("enums"),
            interner.intern("EnumEntries"),
        ]))
        let functionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("enums"),
            interner.intern("enumEntries"),
        ]))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))
        guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
            return XCTFail("enumEntries<T>() should return EnumEntries<T>")
        }
        XCTAssertEqual(returnClassType.classSymbol, enumEntriesSymbol)
        XCTAssertNil(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("enumEntries"),
        ]))
    }

    func testEnumEntriesCompanionPropertyUsesKotlinEnumsEnumEntries() throws {
        let source = """
        enum class Color { RED, BLUE }
        fun noop() {}
        """
        let (sema, interner) = try makeSema(source: source)
        let enumEntriesSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("enums"),
            interner.intern("EnumEntries"),
        ]))
        let entriesSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("Color"),
            interner.intern("Companion"),
            interner.intern("entries"),
        ]))
        let entriesType = try XCTUnwrap(sema.symbols.propertyType(for: entriesSymbol))
        guard case let .classType(entriesClassType) = sema.types.kind(of: entriesType) else {
            return XCTFail("Color.entries should have EnumEntries<Color> type")
        }
        XCTAssertEqual(entriesClassType.classSymbol, enumEntriesSymbol)
    }
}
