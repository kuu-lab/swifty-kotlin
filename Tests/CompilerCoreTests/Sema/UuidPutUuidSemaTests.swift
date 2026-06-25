@testable import CompilerCore
import Foundation
import XCTest

final class UuidPutUuidSemaTests: XCTestCase {

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

    // MARK: - putUuid registration

    func testPutUuidExtensionFunctionIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "uuid", "putUuid"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_byteArray_putUuid"),
            "ByteArray.putUuid must link to kk_byteArray_putUuid; found: \(links)"
        )
    }

    func testPutUuidHasByteArrayReceiver() throws {
        let (sema, interner) = try makeSema()
        let byteArraySym = try XCTUnwrap(
            byteArraySymbol(sema: sema, interner: interner),
            "kotlin.ByteArray must be registered"
        )
        let sym = try XCTUnwrap(
            findByteArrayExtensionSymbol(
                fqPath: ["kotlin", "uuid", "putUuid"],
                byteArraySymbol: byteArraySym,
                sema: sema,
                interner: interner
            ),
            "ByteArray.putUuid extension function must be registered with ByteArray receiver"
        )
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: sym))
        let receiverType = try XCTUnwrap(sig.receiverType)
        guard case .classType(let ct) = sema.types.kind(of: receiverType) else {
            XCTFail("putUuid receiver must be a class type"); return
        }
        XCTAssertEqual(ct.classSymbol, byteArraySym, "putUuid receiver must be kotlin.ByteArray")
    }

    func testPutUuidHasTwoParameters() throws {
        let (sema, interner) = try makeSema()
        let byteArraySym = try XCTUnwrap(byteArraySymbol(sema: sema, interner: interner))
        let sym = try XCTUnwrap(
            findByteArrayExtensionSymbol(
                fqPath: ["kotlin", "uuid", "putUuid"],
                byteArraySymbol: byteArraySym,
                sema: sema,
                interner: interner
            )
        )
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: sym))
        XCTAssertEqual(sig.parameterTypes.count, 2, "putUuid must take exactly 2 parameters (at: Int, uuid: Uuid)")
    }

    func testPutUuidFirstParameterIsInt() throws {
        let (sema, interner) = try makeSema()
        let byteArraySym = try XCTUnwrap(byteArraySymbol(sema: sema, interner: interner))
        let sym = try XCTUnwrap(
            findByteArrayExtensionSymbol(
                fqPath: ["kotlin", "uuid", "putUuid"],
                byteArraySymbol: byteArraySym,
                sema: sema,
                interner: interner
            )
        )
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: sym))
        XCTAssertEqual(
            sig.parameterTypes[0], sema.types.intType,
            "putUuid first parameter (at) must be Int"
        )
    }

    func testPutUuidSecondParameterIsUuid() throws {
        let (sema, interner) = try makeSema()
        let byteArraySym = try XCTUnwrap(byteArraySymbol(sema: sema, interner: interner))
        let sym = try XCTUnwrap(
            findByteArrayExtensionSymbol(
                fqPath: ["kotlin", "uuid", "putUuid"],
                byteArraySymbol: byteArraySym,
                sema: sema,
                interner: interner
            )
        )
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: sym))

        let uuidFQ = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        let uuidSym = try XCTUnwrap(sema.symbols.lookup(fqName: uuidFQ))

        guard case .classType(let ct) = sema.types.kind(of: sig.parameterTypes[1]) else {
            XCTFail("putUuid second parameter must be a class type"); return
        }
        XCTAssertEqual(ct.classSymbol, uuidSym, "putUuid second parameter (uuid) must be kotlin.uuid.Uuid")
    }

    func testPutUuidReturnsUnit() throws {
        let (sema, interner) = try makeSema()
        let byteArraySym = try XCTUnwrap(byteArraySymbol(sema: sema, interner: interner))
        let sym = try XCTUnwrap(
            findByteArrayExtensionSymbol(
                fqPath: ["kotlin", "uuid", "putUuid"],
                byteArraySymbol: byteArraySym,
                sema: sema,
                interner: interner
            )
        )
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: sym))
        XCTAssertEqual(
            sig.returnType, sema.types.unitType,
            "putUuid must return Unit"
        )
    }

    func testPutUuidIsTaggedExperimentalUuidApi() throws {
        let (sema, interner) = try makeSema()
        let interned = ["kotlin", "uuid", "putUuid"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: interned)
        XCTAssertFalse(syms.isEmpty, "putUuid must be registered")
        XCTAssertTrue(
            syms.contains { sym in
                sema.symbols.annotations(for: sym).contains {
                    $0.annotationFQName == "kotlin.uuid.ExperimentalUuidApi"
                }
            },
            "ByteArray.putUuid must carry @ExperimentalUuidApi"
        )
    }

    // MARK: - uuid(at:) registration

    func testUuidAtExtensionFunctionIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "uuid", "uuid"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_byteArray_uuid"),
            "ByteArray.uuid must link to kk_byteArray_uuid; found: \(links)"
        )
    }

    func testUuidAtHasByteArrayReceiver() throws {
        let (sema, interner) = try makeSema()
        let byteArraySym = try XCTUnwrap(byteArraySymbol(sema: sema, interner: interner))
        let sym = try XCTUnwrap(
            findByteArrayExtensionSymbol(
                fqPath: ["kotlin", "uuid", "uuid"],
                byteArraySymbol: byteArraySym,
                sema: sema,
                interner: interner
            ),
            "ByteArray.uuid extension function must be registered with ByteArray receiver"
        )
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: sym))
        let receiverType = try XCTUnwrap(sig.receiverType)
        guard case .classType(let ct) = sema.types.kind(of: receiverType) else {
            XCTFail("uuid receiver must be a class type"); return
        }
        XCTAssertEqual(ct.classSymbol, byteArraySym, "uuid receiver must be kotlin.ByteArray")
    }

    func testUuidAtHasOneParameter() throws {
        let (sema, interner) = try makeSema()
        let byteArraySym = try XCTUnwrap(byteArraySymbol(sema: sema, interner: interner))
        let sym = try XCTUnwrap(
            findByteArrayExtensionSymbol(
                fqPath: ["kotlin", "uuid", "uuid"],
                byteArraySymbol: byteArraySym,
                sema: sema,
                interner: interner
            )
        )
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: sym))
        XCTAssertEqual(sig.parameterTypes.count, 1, "uuid(at:) must take exactly 1 parameter")
        XCTAssertEqual(
            sig.parameterTypes[0], sema.types.intType,
            "uuid(at:) parameter (at) must be Int"
        )
    }

    func testUuidAtReturnsUuid() throws {
        let (sema, interner) = try makeSema()
        let byteArraySym = try XCTUnwrap(byteArraySymbol(sema: sema, interner: interner))
        let sym = try XCTUnwrap(
            findByteArrayExtensionSymbol(
                fqPath: ["kotlin", "uuid", "uuid"],
                byteArraySymbol: byteArraySym,
                sema: sema,
                interner: interner
            )
        )
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: sym))

        let uuidFQ = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        let uuidSym = try XCTUnwrap(sema.symbols.lookup(fqName: uuidFQ))

        guard case .classType(let ct) = sema.types.kind(of: sig.returnType) else {
            XCTFail("uuid(at:) return type must be a class type"); return
        }
        XCTAssertEqual(ct.classSymbol, uuidSym, "uuid(at:) must return kotlin.uuid.Uuid")
    }

    func testUuidAtIsTaggedExperimentalUuidApi() throws {
        let (sema, interner) = try makeSema()
        let interned = ["kotlin", "uuid", "uuid"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: interned)
        XCTAssertFalse(syms.isEmpty, "uuid(at:) must be registered")
        XCTAssertTrue(
            syms.contains { sym in
                sema.symbols.annotations(for: sym).contains {
                    $0.annotationFQName == "kotlin.uuid.ExperimentalUuidApi"
                }
            },
            "ByteArray.uuid must carry @ExperimentalUuidApi"
        )
    }

    // MARK: - Both functions distinct

    func testPutUuidAndUuidAtAreDistinctSymbols() throws {
        let (sema, interner) = try makeSema()
        let putUuidFQ = ["kotlin", "uuid", "putUuid"].map { interner.intern($0) }
        let uuidFQ = ["kotlin", "uuid", "uuid"].map { interner.intern($0) }
        let putUuidSyms = Set(sema.symbols.lookupAll(fqName: putUuidFQ))
        let uuidSyms = Set(sema.symbols.lookupAll(fqName: uuidFQ))
        XCTAssertFalse(putUuidSyms.isEmpty, "putUuid must be registered")
        XCTAssertFalse(uuidSyms.isEmpty, "uuid(at:) must be registered")
        XCTAssertTrue(
            putUuidSyms.isDisjoint(with: uuidSyms),
            "putUuid and uuid(at:) must have distinct SymbolIDs"
        )
    }
}
