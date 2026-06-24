#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

private struct _TestHelperFailure: Error {}

@Suite
struct NativeByteArraySetterSurfaceTests {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

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
        let byteArraySymbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.ByteArray must be registered"
        )
        return sema.types.make(.classType(ClassType(
            classSymbol: byteArraySymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func nativeSetterSignature(
        named name: String,
        valueType: TypeID,
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
                && signature.parameterTypes == [sema.types.intType, valueType]
                && signature.returnType == sema.types.unitType
            {
                return (candidate, signature)
            }
        }

        Issue.record("Expected kotlin.native.\(name) ByteArray setter, got \(candidates.compactMap { sema.symbols.functionSignature(for: $0) })")
        throw _TestHelperFailure()
    }

    @Test func testSignedByteArraySettersAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let expected: [(name: String, valueType: TypeID, linkName: String)] = [
            ("setByteAt", sema.types.intType, "kk_native_byteArray_setByteAt"),
            ("setShortAt", sema.types.intType, "kk_native_byteArray_setShortAt"),
            ("setIntAt", sema.types.intType, "kk_native_byteArray_setIntAt"),
            ("setLongAt", sema.types.longType, "kk_native_byteArray_setLongAt"),
        ]

        for setter in expected {
            let (symbol, signature) = try nativeSetterSignature(
                named: setter.name,
                valueType: setter.valueType,
                sema: sema,
                interner: interner
            )
            #expect(signature.valueParameterHasDefaultValues == [false, false])
            #expect(sema.symbols.externalLinkName(for: symbol) == setter.linkName)
            #expect(
                sema.symbols.annotations(for: symbol).contains {
                    $0.annotationFQName == "kotlin.experimental.ExperimentalNativeApi"
                },
                "\(setter.name) must carry ExperimentalNativeApi metadata"
            )
        }
    }

    @Test func testSignedByteArraySettersResolveInSourceWithOptIn() {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
        import kotlin.native.setByteAt
        import kotlin.native.setShortAt
        import kotlin.native.setIntAt
        import kotlin.native.setLongAt

        fun probe(bytes: ByteArray) {
            bytes.setByteAt(0, -1)
            bytes.setShortAt(1, 0x1234)
            bytes.setIntAt(2, 0x12345678)
            bytes.setLongAt(0, 42L)
        }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        #expect(errors.isEmpty, "Expected signed ByteArray setters to resolve without errors, got \(errors)")
    }
}
#endif
