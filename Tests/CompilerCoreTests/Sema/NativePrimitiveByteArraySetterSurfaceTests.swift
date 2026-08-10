#if canImport(Testing)
@testable import CompilerCore
import Testing

private struct TestAbortError: Error {}

@Suite
struct NativePrimitiveByteArraySetterSurfaceTests {
    @Test func testPrimitiveByteArraySetters() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
        import kotlin.native.setCharAt
        import kotlin.native.setFloatAt
        import kotlin.native.setDoubleAt

        fun probe(bytes: ByteArray, c: Char, f: Float, d: Double) {
            bytes.setCharAt(0, c)
            bytes.setFloatAt(2, f)
            bytes.setDoubleAt(0, d)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected primitive ByteArray setters to resolve without errors, got \(errors)")

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let expected: [(name: String, valueType: TypeID, linkName: String)] = [
            ("setCharAt", sema.types.charType, "kk_native_byteArray_setCharAt"),
            ("setFloatAt", sema.types.floatType, "kk_native_byteArray_setFloatAt"),
            ("setDoubleAt", sema.types.doubleType, "kk_native_byteArray_setDoubleAt"),
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




    private func byteArrayType(
        sema: SemaModule,
        interner: StringInterner
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
        interner: StringInterner
    ) throws -> (SymbolID, FunctionSignature) {
        let nativeFQName = ["kotlin", "native", name].map { interner.intern($0) }
        let receiverType = try byteArrayType(sema: sema, interner: interner)
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
        throw TestAbortError()
    }




}
#endif
