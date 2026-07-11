@testable import CompilerCore
import Foundation
import Testing

// MARK: - KSP-476: ByteArray.putUuid / ByteArray.uuid sema wiring
//
// Both extension functions are pure Kotlin now, declared for real in
// Stdlib/kotlin/uuid/Uuid.kt (no externalLinkName of their own). Verify they
// are source-backed with the expected receiver/parameter/return types and
// @ExperimentalUuidApi opt-in annotations.

@Suite
struct UuidPutUuidSemaTests {

    // MARK: - Shared fixture

    private func makeSemaWithContext() throws -> (CompilationContext, SemaModule, StringInterner) {
        var result: (CompilationContext, SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            result = (ctx, sema, ctx.interner)
        }
        return try #require(result)
    }

    private func makeSema() throws -> (SemaModule, StringInterner) {
        let (_, sema, interner) = try makeSemaWithContext()
        return (sema, interner)
    }

    /// Finds the first symbol at `fqPath` whose receiver type matches `byteArraySymbol`.
    private func findByteArrayExtensionSymbol(
        fqPath: [String],
        byteArraySymbol: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let interned = fqPath.map { interner.intern($0) }
        return sema.symbols.lookupAll(fqName: interned).first { sym in
            guard let sig = sema.symbols.functionSignature(for: sym),
                  let receiverType = sig.receiverType,
                  case .classType(let ct) = sema.types.kind(of: receiverType)
            else { return false }
            return ct.classSymbol == byteArraySymbol
        }
    }

    private func byteArraySymbol(sema: SemaModule, interner: StringInterner) -> SymbolID? {
        let fq = ["kotlin", "ByteArray"].map { interner.intern($0) }
        return sema.symbols.lookup(fqName: fq)
    }

    private func isSourceBacked(
        sym: SymbolID,
        ctx: CompilationContext,
        sema: SemaModule
    ) -> Bool {
        let uuidSourceFileID = ctx.sourceManager.fileID(forPath: "__bundled_kotlin/uuid/Uuid.kt")
        guard let info = sema.symbols.symbol(sym) else { return false }
        return !info.flags.contains(.synthetic) && sema.symbols.sourceFileID(for: sym) == uuidSourceFileID
    }

    // MARK: - putUuid registration

    @Test
    func testPutUuidExtensionFunctionIsSourceBacked() throws {
        let (ctx, sema, interner) = try makeSemaWithContext()
        let byteArraySym = try #require(byteArraySymbol(sema: sema, interner: interner))
        let sym = try #require(
            findByteArrayExtensionSymbol(
                fqPath: ["kotlin", "uuid", "putUuid"],
                byteArraySymbol: byteArraySym,
                sema: sema,
                interner: interner
            )
        )
        #expect(
            isSourceBacked(sym: sym, ctx: ctx, sema: sema),
            "ByteArray.putUuid must be declared in Uuid.kt, not registered as a synthetic stub"
        )
    }

    @Test
    func testPutUuidHasByteArrayReceiver() throws {
        let (sema, interner) = try makeSema()
        let byteArraySym = try #require(
            byteArraySymbol(sema: sema, interner: interner),
            "kotlin.ByteArray must be registered"
        )
        let sym = try #require(
            findByteArrayExtensionSymbol(
                fqPath: ["kotlin", "uuid", "putUuid"],
                byteArraySymbol: byteArraySym,
                sema: sema,
                interner: interner
            ),
            "ByteArray.putUuid extension function must be registered with ByteArray receiver"
        )
        let sig = try #require(sema.symbols.functionSignature(for: sym))
        let receiverType = try #require(sig.receiverType)
        guard case .classType(let ct) = sema.types.kind(of: receiverType) else {
            Issue.record("putUuid receiver must be a class type"); return
        }
        #expect(ct.classSymbol == byteArraySym, "putUuid receiver must be kotlin.ByteArray")
    }

    @Test
    func testPutUuidHasTwoParameters() throws {
        let (sema, interner) = try makeSema()
        let byteArraySym = try #require(byteArraySymbol(sema: sema, interner: interner))
        let sym = try #require(
            findByteArrayExtensionSymbol(
                fqPath: ["kotlin", "uuid", "putUuid"],
                byteArraySymbol: byteArraySym,
                sema: sema,
                interner: interner
            )
        )
        let sig = try #require(sema.symbols.functionSignature(for: sym))
        #expect(sig.parameterTypes.count == 2, "putUuid must take exactly 2 parameters (at: Int, uuid: Uuid)")
    }

    @Test
    func testPutUuidFirstParameterIsInt() throws {
        let (sema, interner) = try makeSema()
        let byteArraySym = try #require(byteArraySymbol(sema: sema, interner: interner))
        let sym = try #require(
            findByteArrayExtensionSymbol(
                fqPath: ["kotlin", "uuid", "putUuid"],
                byteArraySymbol: byteArraySym,
                sema: sema,
                interner: interner
            )
        )
        let sig = try #require(sema.symbols.functionSignature(for: sym))
        #expect(
            sig.parameterTypes[0] == sema.types.intType,
            "putUuid first parameter (at) must be Int"
        )
    }

    @Test
    func testPutUuidSecondParameterIsUuid() throws {
        let (sema, interner) = try makeSema()
        let byteArraySym = try #require(byteArraySymbol(sema: sema, interner: interner))
        let sym = try #require(
            findByteArrayExtensionSymbol(
                fqPath: ["kotlin", "uuid", "putUuid"],
                byteArraySymbol: byteArraySym,
                sema: sema,
                interner: interner
            )
        )
        let sig = try #require(sema.symbols.functionSignature(for: sym))

        let uuidFQ = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        let uuidSym = try #require(sema.symbols.lookup(fqName: uuidFQ))

        guard case .classType(let ct) = sema.types.kind(of: sig.parameterTypes[1]) else {
            Issue.record("putUuid second parameter must be a class type"); return
        }
        #expect(ct.classSymbol == uuidSym, "putUuid second parameter (uuid) must be kotlin.uuid.Uuid")
    }

    @Test
    func testPutUuidReturnsUnit() throws {
        let (sema, interner) = try makeSema()
        let byteArraySym = try #require(byteArraySymbol(sema: sema, interner: interner))
        let sym = try #require(
            findByteArrayExtensionSymbol(
                fqPath: ["kotlin", "uuid", "putUuid"],
                byteArraySymbol: byteArraySym,
                sema: sema,
                interner: interner
            )
        )
        let sig = try #require(sema.symbols.functionSignature(for: sym))
        #expect(
            sig.returnType == sema.types.unitType,
            "putUuid must return Unit"
        )
    }

    @Test
    func testPutUuidIsTaggedExperimentalUuidApi() throws {
        let (sema, interner) = try makeSema()
        let interned = ["kotlin", "uuid", "putUuid"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: interned)
        #expect(!syms.isEmpty, "putUuid must be registered")
        #expect(
            syms.contains { sym in
                sema.symbols.annotations(for: sym).contains {
                    $0.annotationFQName == "kotlin.uuid.ExperimentalUuidApi"
                }
            },
            "ByteArray.putUuid must carry @ExperimentalUuidApi"
        )
    }

    // MARK: - uuid(at:) registration

    @Test
    func testUuidAtExtensionFunctionIsSourceBacked() throws {
        let (ctx, sema, interner) = try makeSemaWithContext()
        let byteArraySym = try #require(byteArraySymbol(sema: sema, interner: interner))
        let sym = try #require(
            findByteArrayExtensionSymbol(
                fqPath: ["kotlin", "uuid", "uuid"],
                byteArraySymbol: byteArraySym,
                sema: sema,
                interner: interner
            )
        )
        #expect(
            isSourceBacked(sym: sym, ctx: ctx, sema: sema),
            "ByteArray.uuid must be declared in Uuid.kt, not registered as a synthetic stub"
        )
    }

    @Test
    func testUuidAtHasByteArrayReceiver() throws {
        let (sema, interner) = try makeSema()
        let byteArraySym = try #require(byteArraySymbol(sema: sema, interner: interner))
        let sym = try #require(
            findByteArrayExtensionSymbol(
                fqPath: ["kotlin", "uuid", "uuid"],
                byteArraySymbol: byteArraySym,
                sema: sema,
                interner: interner
            ),
            "ByteArray.uuid extension function must be registered with ByteArray receiver"
        )
        let sig = try #require(sema.symbols.functionSignature(for: sym))
        let receiverType = try #require(sig.receiverType)
        guard case .classType(let ct) = sema.types.kind(of: receiverType) else {
            Issue.record("uuid receiver must be a class type"); return
        }
        #expect(ct.classSymbol == byteArraySym, "uuid receiver must be kotlin.ByteArray")
    }

    @Test
    func testUuidAtHasOneParameter() throws {
        let (sema, interner) = try makeSema()
        let byteArraySym = try #require(byteArraySymbol(sema: sema, interner: interner))
        let sym = try #require(
            findByteArrayExtensionSymbol(
                fqPath: ["kotlin", "uuid", "uuid"],
                byteArraySymbol: byteArraySym,
                sema: sema,
                interner: interner
            )
        )
        let sig = try #require(sema.symbols.functionSignature(for: sym))
        #expect(sig.parameterTypes.count == 1, "uuid(at:) must take exactly 1 parameter")
        #expect(
            sig.parameterTypes[0] == sema.types.intType,
            "uuid(at:) parameter (at) must be Int"
        )
    }

    @Test
    func testUuidAtReturnsUuid() throws {
        let (sema, interner) = try makeSema()
        let byteArraySym = try #require(byteArraySymbol(sema: sema, interner: interner))
        let sym = try #require(
            findByteArrayExtensionSymbol(
                fqPath: ["kotlin", "uuid", "uuid"],
                byteArraySymbol: byteArraySym,
                sema: sema,
                interner: interner
            )
        )
        let sig = try #require(sema.symbols.functionSignature(for: sym))

        let uuidFQ = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        let uuidSym = try #require(sema.symbols.lookup(fqName: uuidFQ))

        guard case .classType(let ct) = sema.types.kind(of: sig.returnType) else {
            Issue.record("uuid(at:) return type must be a class type"); return
        }
        #expect(ct.classSymbol == uuidSym, "uuid(at:) must return kotlin.uuid.Uuid")
    }

    @Test
    func testUuidAtIsTaggedExperimentalUuidApi() throws {
        let (sema, interner) = try makeSema()
        let interned = ["kotlin", "uuid", "uuid"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: interned)
        #expect(!syms.isEmpty, "uuid(at:) must be registered")
        #expect(
            syms.contains { sym in
                sema.symbols.annotations(for: sym).contains {
                    $0.annotationFQName == "kotlin.uuid.ExperimentalUuidApi"
                }
            },
            "ByteArray.uuid must carry @ExperimentalUuidApi"
        )
    }

    // MARK: - Both functions distinct

    @Test
    func testPutUuidAndUuidAtAreDistinctSymbols() throws {
        let (sema, interner) = try makeSema()
        let putUuidFQ = ["kotlin", "uuid", "putUuid"].map { interner.intern($0) }
        let uuidFQ = ["kotlin", "uuid", "uuid"].map { interner.intern($0) }
        let putUuidSyms = Set(sema.symbols.lookupAll(fqName: putUuidFQ))
        let uuidSyms = Set(sema.symbols.lookupAll(fqName: uuidFQ))
        #expect(!putUuidSyms.isEmpty, "putUuid must be registered")
        #expect(!uuidSyms.isEmpty, "uuid(at:) must be registered")
        #expect(
            putUuidSyms.isDisjoint(with: uuidSyms),
            "putUuid and uuid(at:) must have distinct SymbolIDs"
        )
    }
}
