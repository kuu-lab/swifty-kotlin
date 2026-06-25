@testable import CompilerCore
import XCTest

final class ThrowablePrintStackTraceSyntheticTests: XCTestCase {
    func testPrintStackTraceMemberFunctionIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let kotlinPackage = ["kotlin"].map { interner.intern($0) }
        let throwableSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: kotlinPackage + [interner.intern("Throwable")]
        ))
        let throwableType = sema.types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nonNull
        )))

        let printStackTraceSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: kotlinPackage + [interner.intern("Throwable"), interner.intern("printStackTrace")]
        ))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: printStackTraceSymbol))

        XCTAssertEqual(sema.symbols.externalLinkName(for: printStackTraceSymbol), "kk_throwable_printStackTrace")
        XCTAssertEqual(signature.receiverType, throwableType)
        XCTAssertEqual(signature.parameterTypes, [])
        XCTAssertEqual(signature.returnType, sema.types.unitType)
    }

    func testPrintStackTraceResolvesAsUnitReturningMemberCall() throws {
        let source = """
        fun sample(e: Throwable) {
            val result: Unit = e.printStackTrace()
        }
        """

        let (sema, interner) = try makeSema(source: source)
        let sampleSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: [interner.intern("sample")]
        ))

        XCTAssertNotNil(sema.symbols.functionSignature(for: sampleSymbol))
    }
}
