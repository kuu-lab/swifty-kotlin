@testable import CompilerCore
import Foundation
import XCTest

final class UuidFromLongsFromByteArraySemaTests: XCTestCase {

    // MARK: - fromLongs

    func testUuidFromLongsCompanionMethodIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "uuid", "Uuid", "Companion", "fromLongs"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_uuid_fromLongs"),
            "Uuid.fromLongs() must link to kk_uuid_fromLongs; found: \(links)"
        )
    }

    func testUuidFromLongsAcceptsTwoLongParameters() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "fromLongs"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        XCTAssertFalse(syms.isEmpty, "Uuid.fromLongs must be registered")
        let sym = try XCTUnwrap(syms.first)
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            XCTFail("Uuid.fromLongs has no signature"); return
        }
        XCTAssertEqual(sig.parameterTypes.count, 2, "Uuid.fromLongs must take 2 Long parameters")
        XCTAssertEqual(sig.parameterTypes[0], sema.types.longType, "first param must be Long")
        XCTAssertEqual(sig.parameterTypes[1], sema.types.longType, "second param must be Long")
    }

    func testUuidFromLongsReturnTypeIsUuid() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "fromLongs"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        XCTAssertFalse(syms.isEmpty, "Uuid.fromLongs must be registered")
        let sym = try XCTUnwrap(syms.first)
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            XCTFail("Uuid.fromLongs has no signature"); return
        }
        let uuidFQ = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        guard let uuidSym = sema.symbols.lookup(fqName: uuidFQ) else {
            XCTFail("kotlin.uuid.Uuid class symbol missing"); return
        }
        let returnTypeKind = sema.types.kind(of: sig.returnType)
        if case .classType(let ct) = returnTypeKind {
            XCTAssertEqual(ct.classSymbol, uuidSym, "Uuid.fromLongs return type must be kotlin.uuid.Uuid")
        } else {
            XCTFail("Uuid.fromLongs return type is not a class type; got \(returnTypeKind)")
        }
    }

    // MARK: - fromByteArray

    func testUuidFromByteArrayCompanionMethodIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "uuid", "Uuid", "Companion", "fromByteArray"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_uuid_fromByteArray"),
            "Uuid.fromByteArray() must link to kk_uuid_fromByteArray; found: \(links)"
        )
    }

    func testUuidFromByteArrayAcceptsOneParameter() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "fromByteArray"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        XCTAssertFalse(syms.isEmpty, "Uuid.fromByteArray must be registered")
        let sym = try XCTUnwrap(syms.first)
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            XCTFail("Uuid.fromByteArray has no signature"); return
        }
        XCTAssertEqual(sig.parameterTypes.count, 1, "Uuid.fromByteArray must take 1 parameter")
    }

    func testUuidFromByteArrayReturnTypeIsUuid() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "fromByteArray"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        XCTAssertFalse(syms.isEmpty, "Uuid.fromByteArray must be registered")
        let sym = try XCTUnwrap(syms.first)
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            XCTFail("Uuid.fromByteArray has no signature"); return
        }
        let uuidFQ = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        guard let uuidSym = sema.symbols.lookup(fqName: uuidFQ) else {
            XCTFail("kotlin.uuid.Uuid class symbol missing"); return
        }
        let returnTypeKind = sema.types.kind(of: sig.returnType)
        if case .classType(let ct) = returnTypeKind {
            XCTAssertEqual(ct.classSymbol, uuidSym, "Uuid.fromByteArray return type must be kotlin.uuid.Uuid")
        } else {
            XCTFail("Uuid.fromByteArray return type is not a class type; got \(returnTypeKind)")
        }
    }

    // MARK: - Full companion link surface

    func testAllNewCompanionLinksArePresent() throws {
        let (sema, interner) = try makeSema()
        let companionFQ = ["kotlin", "uuid", "Uuid", "Companion"]
        let requiredLinks: Set<String> = [
            "kk_uuid_fromLongs",
            "kk_uuid_fromByteArray",
        ]
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
        XCTAssertTrue(
            requiredLinks.isSubset(of: foundLinks),
            "fromLongs and fromByteArray companion methods must be registered; found: \(foundLinks)"
        )
    }
}
