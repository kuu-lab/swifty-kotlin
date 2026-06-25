@testable import CompilerCore
import XCTest

final class JsArrayExternalClassTests: XCTestCase {
    func testJsArrayClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "JsArray"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.js.JsArray must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .class)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertNotNil(sema.symbols.propertyType(for: symbol))
    }



    private func arrayType(element: TypeID, sema: SemaModule, interner: StringInterner) throws -> TypeID {
        let arrayFQName = ["kotlin", "Array"].map { interner.intern($0) }
        let arraySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: arrayFQName))
        return sema.types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [.invariant(element)],
            nullability: .nonNull
        )))
    }
}
