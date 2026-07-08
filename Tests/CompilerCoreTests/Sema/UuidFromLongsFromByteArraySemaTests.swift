@testable import CompilerCore
import Foundation
import Testing

// MARK: - STDLIB-UUID-ABI-001/002: Uuid.fromLongs and Uuid.fromByteArray source declarations
//
// Verifies that fromLongs(msb, lsb) and fromByteArray(byteArray) companion factory
// methods are sourced from Stdlib/kotlin/uuid/Uuid.kt without pure runtime links.

@Suite
struct UuidFromLongsFromByteArraySemaTests {

    // MARK: - Shared sema fixture

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            result = (sema, ctx.interner)
        }
        return try #require(result)
    }

    // MARK: - Lookup helpers

    private func allExternalLinks(
        fqPath: [String],
        sema: SemaModule,
        interner: StringInterner
    ) -> Set<String> {
        let interned = fqPath.map { interner.intern($0) }
        return Set(
            sema.symbols.lookupAll(fqName: interned)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
    }

    // MARK: - fromLongs

    @Test
    func testUuidFromLongsCompanionMethodIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "uuid", "Uuid", "Companion", "fromLongs"],
            sema: sema,
            interner: interner
        )
        #expect(
            links.isEmpty,
            "Uuid.fromLongs() must be Kotlin source-backed, not linked to kk_uuid_fromLongs; found: \(links)"
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
    func testUuidFromByteArrayCompanionMethodIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "uuid", "Uuid", "Companion", "fromByteArray"],
            sema: sema,
            interner: interner
        )
        #expect(
            links.isEmpty,
            "Uuid.fromByteArray() must be Kotlin source-backed, not linked to kk_uuid_fromByteArray; found: \(links)"
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

    // MARK: - Full companion source surface

    @Test
    func testMigratedCompanionFactoriesHaveNoPureRuntimeLinks() throws {
        let (sema, interner) = try makeSema()
        let companionFQ = ["kotlin", "uuid", "Uuid", "Companion"]
        var foundLinks: Set<String> = []
        for memberName in ["fromLongs", "fromByteArray"] {
            let path = companionFQ + [memberName]
            let interned = path.map { interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: interned)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            foundLinks.formUnion(links)
        }
        #expect(
            foundLinks.isEmpty,
            "fromLongs and fromByteArray must not register pure runtime links; found: \(foundLinks)"
        )
    }
}
