#if canImport(Testing)
@testable import CompilerCore
import Testing

private struct TestAbortError: Error {}

@Suite
struct NativeImmutableBlobSurfaceTests {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = (try #require(ctx.sema), ctx.interner)
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

    private func symbol(
        _ fqPath: [String],
        sema: SemaModule,
        interner: StringInterner
    ) throws -> SymbolID {
            let found = sema.symbols.lookup(fqName: fqPath.map { interner.intern($0) })
        return try requireTestValue(found, "\(fqPath.joined(separator: ".")) must be registered")
    }

    private func classType(
        _ fqPath: [String],
        sema: SemaModule,
        interner: StringInterner,
        args: [TypeArg] = []
    ) throws -> TypeID {
        let classSymbol = try symbol(fqPath, sema: sema, interner: interner)
        return sema.types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: args,
            nullability: .nonNull
        )))
    }

    private func immutableBlobType(
        sema: SemaModule,
        interner: StringInterner
    ) throws -> TypeID {
        try classType(["kotlin", "native", "ImmutableBlob"], sema: sema, interner: interner)
    }

    private func memberSignature(
        named name: String,
        parameters: [TypeID],
        returnType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) throws -> (SymbolID, FunctionSignature) {
        let ownerSymbol = try symbol(["kotlin", "native", "ImmutableBlob"], sema: sema, interner: interner)
        let ownerFQName = try #require(sema.symbols.symbol(ownerSymbol)?.fqName)
        let receiver = try immutableBlobType(sema: sema, interner: interner)
        let candidates = sema.symbols.lookupAll(fqName: ownerFQName + [interner.intern(name)])
        for candidate in candidates {
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                continue
            }
            if signature.receiverType == receiver
                && signature.parameterTypes == parameters
                && signature.returnType == returnType
            {
                return (candidate, signature)
            }
        }

        Issue.record("Expected ImmutableBlob.\(name) signature, got \(candidates.compactMap { sema.symbols.functionSignature(for: $0) })")
        throw TestAbortError()
    }

    private func topLevelSignature(
        named name: String,
        receiverType: TypeID?,
        parameters: [TypeID],
        returnType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) throws -> (SymbolID, FunctionSignature) {
        let fqName = ["kotlin", "native", name].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fqName)
        for candidate in candidates {
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                continue
            }
            if signature.receiverType == receiverType
                && signature.parameterTypes == parameters
                && signature.returnType == returnType
            {
                return (candidate, signature)
            }
        }

        Issue.record("Expected kotlin.native.\(name) signature, got \(candidates.compactMap { sema.symbols.functionSignature(for: $0) })")
        throw TestAbortError()
    }

    @Test
    func testImmutableBlobClassIsRegisteredWithDeprecationMetadata() throws {
        let (sema, interner) = try makeSema()
        let blob = try symbol(["kotlin", "native", "ImmutableBlob"], sema: sema, interner: interner)
        let annotations = sema.symbols.annotations(for: blob)

        #expect(sema.symbols.symbol(blob)?.kind == .class)
        #expect(
            annotations.contains { $0.annotationFQName == "kotlin.Deprecated" },
            "ImmutableBlob must carry @Deprecated metadata"
        )
        #expect(
            annotations.contains { $0.annotationFQName == "kotlin.DeprecatedSinceKotlin" },
            "ImmutableBlob must carry @DeprecatedSinceKotlin metadata"
        )
    }

    @Test
    func testImmutableBlobMembersAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let blob = try symbol(["kotlin", "native", "ImmutableBlob"], sema: sema, interner: interner)
        let ownerFQName = try #require(sema.symbols.symbol(blob)?.fqName)
        let size = try #require(sema.symbols.lookup(fqName: ownerFQName + [interner.intern("size")]))
        let byteIterator = try classType(["kotlin", "ByteIterator"], sema: sema, interner: interner)

        #expect(sema.symbols.propertyType(for: size) == sema.types.intType)
        let (getSymbol, _) = try memberSignature(
            named: "get",
            parameters: [sema.types.intType],
            returnType: sema.types.intType,
            sema: sema,
            interner: interner
        )
        #expect(sema.symbols.symbol(getSymbol)?.flags.contains(.operatorFunction) == true)
        let (iteratorSymbol, iteratorSignature) = try memberSignature(
            named: "iterator",
            parameters: [],
            returnType: byteIterator,
            sema: sema,
            interner: interner
        )
        #expect(sema.symbols.symbol(iteratorSymbol)?.flags.contains(.operatorFunction) == true)
        #expect(iteratorSignature.parameterTypes.isEmpty)
    }

    @Test
    func testImmutableBlobFactoryIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let blobType = try immutableBlobType(sema: sema, interner: interner)
        let (factory, signature) = try topLevelSignature(
            named: "immutableBlobOf",
            receiverType: nil,
            parameters: [sema.types.intType],
            returnType: blobType,
            sema: sema,
            interner: interner
        )
        let annotations = sema.symbols.annotations(for: factory)

        #expect(signature.valueParameterIsVararg == [true])
        #expect(
            annotations.contains { $0.annotationFQName == "kotlin.Deprecated" },
            "immutableBlobOf must carry @Deprecated metadata"
        )
        #expect(
            annotations.contains { $0.annotationFQName == "kotlin.DeprecatedSinceKotlin" },
            "immutableBlobOf must carry @DeprecatedSinceKotlin metadata"
        )
    }

    @Test
    func testImmutableBlobExtensionFunctionsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let blobType = try immutableBlobType(sema: sema, interner: interner)
        let byteArrayType = try classType(["kotlin", "ByteArray"], sema: sema, interner: interner)
        let uByteArrayType = try classType(["kotlin", "UByteArray"], sema: sema, interner: interner)
        let byteVarType = try classType(["kotlinx", "cinterop", "ByteVar"], sema: sema, interner: interner)
        let uByteVarType = try classType(["kotlinx", "cinterop", "UByteVar"], sema: sema, interner: interner)
        let cPointerByteVarType = try classType(
            ["kotlinx", "cinterop", "CPointer"],
            sema: sema,
            interner: interner,
            args: [.invariant(byteVarType)]
        )
        let cPointerUByteVarType = try classType(
            ["kotlinx", "cinterop", "CPointer"],
            sema: sema,
            interner: interner,
            args: [.invariant(uByteVarType)]
        )

        let (_, toByteArray) = try topLevelSignature(
            named: "toByteArray",
            receiverType: blobType,
            parameters: [sema.types.intType, sema.types.intType],
            returnType: byteArrayType,
            sema: sema,
            interner: interner
        )
        let (toUByteArraySymbol, toUByteArray) = try topLevelSignature(
            named: "toUByteArray",
            receiverType: blobType,
            parameters: [sema.types.intType, sema.types.intType],
            returnType: uByteArrayType,
            sema: sema,
            interner: interner
        )
        let (_, asCPointer) = try topLevelSignature(
            named: "asCPointer",
            receiverType: blobType,
            parameters: [sema.types.intType],
            returnType: cPointerByteVarType,
            sema: sema,
            interner: interner
        )
        let (_, asUCPointer) = try topLevelSignature(
            named: "asUCPointer",
            receiverType: blobType,
            parameters: [sema.types.intType],
            returnType: cPointerUByteVarType,
            sema: sema,
            interner: interner
        )

        #expect(toByteArray.valueParameterHasDefaultValues == [true, true])
        #expect(toUByteArray.valueParameterHasDefaultValues == [true, true])
        #expect(asCPointer.valueParameterHasDefaultValues == [true])
        #expect(asUCPointer.valueParameterHasDefaultValues == [true])
        #expect(
            sema.symbols.annotations(for: toUByteArraySymbol).contains { $0.annotationFQName == "kotlin.ExperimentalUnsignedTypes" },
            "toUByteArray must carry @ExperimentalUnsignedTypes metadata"
        )
    }

    @Test
    func testImmutableBlobSurfaceResolvesInSource() {
        let source = """
        @file:OptIn(kotlin.ExperimentalUnsignedTypes::class)
        import kotlin.native.ImmutableBlob
        import kotlin.native.immutableBlobOf

        fun probe(blob: ImmutableBlob): Int {
            val made = immutableBlobOf(1, 2, 255)
            val first = blob[0]
            val copy = blob.toByteArray()
            val unsigned = blob.toUByteArray()
            blob.asCPointer()
            blob.asUCPointer()
            return first + blob.size + made.size + copy.size + unsigned.size
        }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        #expect(
            errors.isEmpty,
            "Expected ImmutableBlob surface to type-check, got \(errors)"
        )
    }
}
#endif
