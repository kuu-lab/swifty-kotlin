@testable import CompilerCore
import XCTest

final class DynamicExternalInterfaceTests: XCTestCase {
    func testDynamicInterfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "Dynamic"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.js.Dynamic must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .interface)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertNotNil(sema.symbols.propertyType(for: symbol))
    }

    func testDynamicIteratorIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let dynamicFQName = ["kotlin", "js", "Dynamic"].map { interner.intern($0) }
        let dynamicSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: dynamicFQName))
        let dynamicType = try XCTUnwrap(sema.symbols.propertyType(for: dynamicSymbol))
        let iteratorSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlin", "collections", "Iterator"].map { interner.intern($0) })
        )

        let iteratorFunction = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: dynamicFQName + [interner.intern("iterator")]).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID),
                      case let .classType(returnType) = sema.types.kind(of: signature.returnType)
                else {
                    return false
                }
                return signature.receiverType == dynamicType
                    && signature.parameterTypes.isEmpty
                    && returnType.classSymbol == iteratorSymbol
                    && returnType.args.count == 1
            },
            "Dynamic.iterator() member must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(iteratorFunction))

        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertTrue(info.flags.contains(.operatorFunction))
        XCTAssertEqual(sema.symbols.externalLinkName(for: iteratorFunction), "kk_dynamic_iterator")
    }

    func testDynamicIteratorResolvesFromSource() throws {
        let source = """
        import kotlin.js.Dynamic
        import kotlin.collections.Iterator

        fun iteratorOf(value: Dynamic): Iterator<Dynamic> = value.iterator()
        """
        let (sema, interner) = try makeSema(source: source)

        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern("iteratorOf")]))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
        guard case .classType = sema.types.kind(of: signature.returnType) else {
            return XCTFail("iteratorOf should return Iterator<Dynamic>, got \(sema.types.renderType(signature.returnType))")
        }
    }
}
