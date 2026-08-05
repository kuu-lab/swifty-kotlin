#if canImport(Testing)
@testable import CompilerCore
import Testing

private struct TestAbortError: Error {}

@Suite
struct NativeUnsignedByteArraySetterSurfaceTests {
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

    @Test
    func testUnsignedByteArraySetters() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
        @file:OptIn(kotlin.ExperimentalUnsignedTypes::class)
        import kotlin.native.setUByteAt
        import kotlin.native.setUShortAt
        import kotlin.native.setUIntAt
        import kotlin.native.setULongAt

        fun probe(bytes: ByteArray, ub: UByte, us: UShort, ui: UInt, ul: ULong) {
            bytes.setUByteAt(0, ub)
            bytes.setUShortAt(1, us)
            bytes.setUIntAt(2, ui)
            bytes.setULongAt(0, ul)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected unsigned ByteArray setters to resolve without errors, got \(errors)")

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let expected: [(name: String, valueType: TypeID, linkName: String)] = [
            ("setUByteAt", sema.types.ubyteType, "kk_native_byteArray_setUByteAt"),
            ("setUShortAt", sema.types.ushortType, "kk_native_byteArray_setUShortAt"),
            ("setUIntAt", sema.types.uintType, "kk_native_byteArray_setUIntAt"),
            ("setULongAt", sema.types.ulongType, "kk_native_byteArray_setULongAt"),
        ]

        for setter in expected {
            let (symbol, signature) = try nativeSetterSignature(
                named: setter.name,
                valueType: setter.valueType,
                sema: sema,
                interner: interner
            )
            let annotations = sema.symbols.annotations(for: symbol)
            #expect(signature.valueParameterHasDefaultValues == [false, false])
            #expect(sema.symbols.externalLinkName(for: symbol) == setter.linkName)
            #expect(
                annotations.contains { $0.annotationFQName == "kotlin.experimental.ExperimentalNativeApi" },
                "\(setter.name) must carry ExperimentalNativeApi metadata"
            )
            #expect(
                annotations.contains { $0.annotationFQName == "kotlin.ExperimentalUnsignedTypes" },
                "\(setter.name) must carry ExperimentalUnsignedTypes metadata"
            )
        }
    }
}
#endif
