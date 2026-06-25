@testable import CompilerCore
import Foundation
import XCTest

final class NativeByteArrayAccessorSurfaceTests: XCTestCase {
    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Tests assert on collected diagnostics.
        }
        return ctx
    }

    private func byteArrayType(
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> TypeID {
        let fqName = ["kotlin", "ByteArray"].map { interner.intern($0) }
        let byteArraySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.ByteArray must be registered",
            file: file,
            line: line
        )
        return sema.types.make(.classType(ClassType(
            classSymbol: byteArraySymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func nativeAccessorSignature(
        named name: String,
        returnType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (SymbolID, FunctionSignature) {
        let nativeFQName = ["kotlin", "native", name].map { interner.intern($0) }
        let receiverType = try byteArrayType(sema: sema, interner: interner, file: file, line: line)
        let candidates = sema.symbols.lookupAll(fqName: nativeFQName)
        for candidate in candidates {
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                continue
            }
            if signature.receiverType == receiverType
                && signature.parameterTypes == [sema.types.intType]
                && signature.returnType == returnType
            {
                return (candidate, signature)
            }
        }

        XCTFail("Expected kotlin.native.\(name) ByteArray accessor, got \(candidates.compactMap { sema.symbols.functionSignature(for: $0) })", file: file, line: line)
        throw XCTestError(.failureWhileWaiting)
    }

    func testSignedByteArrayAccessorsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let expected: [(name: String, returnType: TypeID, linkName: String)] = [
            ("getByteAt", sema.types.intType, "kk_native_byteArray_getByteAt"),
            ("getShortAt", sema.types.intType, "kk_native_byteArray_getShortAt"),
            ("getIntAt", sema.types.intType, "kk_native_byteArray_getIntAt"),
            ("getLongAt", sema.types.longType, "kk_native_byteArray_getLongAt"),
        ]

        for accessor in expected {
            let (symbol, signature) = try nativeAccessorSignature(
                named: accessor.name,
                returnType: accessor.returnType,
                sema: sema,
                interner: interner
            )
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbol), accessor.linkName)
            XCTAssertTrue(
                sema.symbols.annotations(for: symbol).contains {
                    $0.annotationFQName == "kotlin.experimental.ExperimentalNativeApi"
                },
                "\(accessor.name) must carry ExperimentalNativeApi metadata"
            )
        }
    }

    func testSignedByteArrayAccessorsResolveInSourceWithOptIn() {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
        import kotlin.native.getByteAt
        import kotlin.native.getShortAt
        import kotlin.native.getIntAt
        import kotlin.native.getLongAt

        fun probe(bytes: ByteArray): Long {
            val byteValue = bytes.getByteAt(0)
            val shortValue = bytes.getShortAt(1)
            val intValue = bytes.getIntAt(2)
            val longValue = bytes.getLongAt(0)
            return longValue + byteValue + shortValue + intValue
        }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        XCTAssertTrue(errors.isEmpty, "Expected signed ByteArray accessors to resolve without errors, got \(errors)")
    }
}
