@testable import CompilerCore
import XCTest

final class NativeGetterAnnotationTests: XCTestCase {
    func testNativeGetterAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "nativeGetter"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.js.nativeGetter must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .annotationClass)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
    }

    func testNativeGetterCarriesExpectedMetadata() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "nativeGetter"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let target = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
            "nativeGetter must carry @Target metadata"
        )
        let deprecated = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.Deprecated" },
            "nativeGetter must carry Deprecated metadata"
        )

        XCTAssertEqual(Set(target.arguments), Set(["AnnotationTarget.FUNCTION"]))
        XCTAssertEqual(
            deprecated.arguments,
            ["message = \"Use inline extension function with body using dynamic\""]
        )
    }
}
