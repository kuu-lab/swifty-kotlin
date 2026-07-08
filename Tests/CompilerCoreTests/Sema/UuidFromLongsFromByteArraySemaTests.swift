@testable import CompilerCore
import Foundation
import Testing

// MARK: - KSP-476: Uuid.fromLongs and Uuid.fromByteArray sema wiring
//
// fromLongs delegates to a private native bridge (__kk_uuid_fromLongs);
// fromByteArray is now pure Kotlin built on top of fromLongs. Both are
// declared for real in Stdlib/kotlin/uuid/Uuid.kt, so neither carries an
// externalLinkName of its own anymore — verify they are source-backed
// (not synthetic) with the expected signature instead.

@Suite
struct UuidFromLongsFromByteArraySemaTests {

    // MARK: - Shared sema fixture

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

    private func isSourceBacked(
        fqPath: [String],
        ctx: CompilationContext,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let uuidSourceFileID = ctx.sourceManager.fileID(forPath: "__bundled_kotlin/uuid/Uuid.kt")
        let interned = fqPath.map { interner.intern($0) }
        return sema.symbols.lookupAll(fqName: interned).contains { sym in
            guard let info = sema.symbols.symbol(sym) else { return false }
            return !info.flags.contains(.synthetic) && sema.symbols.sourceFileID(for: sym) == uuidSourceFileID
        }
    }

    // MARK: - fromLongs

    @Test
    func testUuidFromLongsCompanionMethodIsSourceBacked() throws {
        let (ctx, sema, interner) = try makeSemaWithContext()
        #expect(
            isSourceBacked(
                fqPath: ["kotlin", "uuid", "Uuid", "Companion", "fromLongs"],
                ctx: ctx,
                sema: sema,
                interner: interner
            ),
            "Uuid.fromLongs() must be declared in Uuid.kt, not registered as a synthetic stub"
        )
    }

    @Test
    func testUuidFromLongsAcceptsTwoLongParameters() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "fromLongs"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        #expect(!syms.isEmpty, "Uuid.fromLongs must be registered")
        let sym = try #require(syms.first)
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            Issue.record("Uuid.fromLongs has no signature"); return
        }
        #expect(sig.parameterTypes.count == 2, "Uuid.fromLongs must take 2 Long parameters")
        #expect(sig.parameterTypes[0] == sema.types.longType, "first param must be Long")
        #expect(sig.parameterTypes[1] == sema.types.longType, "second param must be Long")
    }

    @Test
    func testUuidFromLongsReturnTypeIsUuid() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "fromLongs"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        #expect(!syms.isEmpty, "Uuid.fromLongs must be registered")
        let sym = try #require(syms.first)
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            Issue.record("Uuid.fromLongs has no signature"); return
        }
        let uuidFQ = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        guard let uuidSym = sema.symbols.lookup(fqName: uuidFQ) else {
            Issue.record("kotlin.uuid.Uuid class symbol missing"); return
        }
        let returnTypeKind = sema.types.kind(of: sig.returnType)
        if case .classType(let ct) = returnTypeKind {
            #expect(ct.classSymbol == uuidSym, "Uuid.fromLongs return type must be kotlin.uuid.Uuid")
        } else {
            Issue.record("Uuid.fromLongs return type is not a class type; got \(returnTypeKind)")
        }
    }

    // MARK: - fromByteArray

    @Test
    func testUuidFromByteArrayCompanionMethodIsSourceBacked() throws {
        let (ctx, sema, interner) = try makeSemaWithContext()
        #expect(
            isSourceBacked(
                fqPath: ["kotlin", "uuid", "Uuid", "Companion", "fromByteArray"],
                ctx: ctx,
                sema: sema,
                interner: interner
            ),
            "Uuid.fromByteArray() must be declared in Uuid.kt, not registered as a synthetic stub"
        )
    }

    @Test
    func testUuidFromByteArrayAcceptsOneParameter() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "fromByteArray"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        #expect(!syms.isEmpty, "Uuid.fromByteArray must be registered")
        let sym = try #require(syms.first)
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            Issue.record("Uuid.fromByteArray has no signature"); return
        }
        #expect(sig.parameterTypes.count == 1, "Uuid.fromByteArray must take 1 parameter")
    }

    @Test
    func testUuidFromByteArrayReturnTypeIsUuid() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "fromByteArray"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        #expect(!syms.isEmpty, "Uuid.fromByteArray must be registered")
        let sym = try #require(syms.first)
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            Issue.record("Uuid.fromByteArray has no signature"); return
        }
        let uuidFQ = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        guard let uuidSym = sema.symbols.lookup(fqName: uuidFQ) else {
            Issue.record("kotlin.uuid.Uuid class symbol missing"); return
        }
        let returnTypeKind = sema.types.kind(of: sig.returnType)
        if case .classType(let ct) = returnTypeKind {
            #expect(ct.classSymbol == uuidSym, "Uuid.fromByteArray return type must be kotlin.uuid.Uuid")
        } else {
            Issue.record("Uuid.fromByteArray return type is not a class type; got \(returnTypeKind)")
        }
    }
}
