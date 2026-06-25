@testable import CompilerCore
import Foundation
import XCTest

// Verifies that ByteArray.getUuid(offset: Int) is registered as a synthetic
// extension in the kotlin.uuid package with the correct ABI external-link name,
// receiver type, parameter signature, return type, and @ExperimentalUuidApi annotation.

final class UuidGetUuidSemaTests: XCTestCase {

    // MARK: - Registration presence

    func testGetUuidIsRegisteredInKotlinUuidPackage() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "getUuid"].map { interner.intern($0) }
        XCTAssertFalse(
            sema.symbols.lookupAll(fqName: fq).isEmpty,
            "ByteArray.getUuid must be registered in kotlin.uuid package"
        )
    }

    // MARK: - External link name

    func testGetUuidLinksToKkUuidGetUuid() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "getUuid"].map { interner.intern($0) }
        let links = Set(
            sema.symbols.lookupAll(fqName: fq)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        XCTAssertTrue(
            links.contains("kk_uuid_getUuid"),
            "getUuid must link to kk_uuid_getUuid; found: \(links)"
        )
    }

    // MARK: - Receiver type

    func testGetUuidHasByteArrayReceiverType() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "getUuid"].map { interner.intern($0) }
        let sym = try XCTUnwrap(sema.symbols.lookupAll(fqName: fq).first)
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            XCTFail("getUuid has no signature"); return
        }
        guard let receiverType = sig.receiverType else {
            XCTFail("getUuid must have a receiver type (ByteArray)"); return
        }
        let byteArrayFQ = ["kotlin", "ByteArray"].map { interner.intern($0) }
        guard let byteArraySym = sema.symbols.lookup(fqName: byteArrayFQ) else {
            XCTFail("kotlin.ByteArray class symbol missing"); return
        }
        if case .classType(let ct) = sema.types.kind(of: receiverType) {
            XCTAssertEqual(ct.classSymbol, byteArraySym, "getUuid receiver must be kotlin.ByteArray")
        } else {
            XCTFail("getUuid receiver type is not a class type; got \(sema.types.kind(of: receiverType))")
        }
    }

    // MARK: - Parameters

    func testGetUuidHasOneIntParameter() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "getUuid"].map { interner.intern($0) }
        let sym = try XCTUnwrap(sema.symbols.lookupAll(fqName: fq).first)
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            XCTFail("getUuid has no signature"); return
        }
        XCTAssertEqual(sig.parameterTypes.count, 1, "getUuid must accept exactly one parameter (offset: Int)")
        XCTAssertEqual(sig.parameterTypes.first, sema.types.intType, "offset parameter must be Int")
    }

    // MARK: - Return type

    func testGetUuidReturnsUuid() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "getUuid"].map { interner.intern($0) }
        let sym = try XCTUnwrap(sema.symbols.lookupAll(fqName: fq).first)
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            XCTFail("getUuid has no signature"); return
        }
        let uuidFQ = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        guard let uuidSym = sema.symbols.lookup(fqName: uuidFQ) else {
            XCTFail("kotlin.uuid.Uuid class symbol missing"); return
        }
        if case .classType(let ct) = sema.types.kind(of: sig.returnType) {
            XCTAssertEqual(ct.classSymbol, uuidSym, "getUuid return type must be kotlin.uuid.Uuid")
        } else {
            XCTFail("getUuid return type is not a class type; got \(sema.types.kind(of: sig.returnType))")
        }
    }

    // MARK: - Symbol flags

    func testGetUuidIsMarkedThrowingFunction() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "getUuid"].map { interner.intern($0) }
        let sym = try XCTUnwrap(sema.symbols.lookupAll(fqName: fq).first)
        guard let info = sema.symbols.symbol(sym) else {
            XCTFail("getUuid symbol info missing"); return
        }
        XCTAssertTrue(
            info.flags.contains(.throwingFunction),
            "getUuid must be marked .throwingFunction (it throws IndexOutOfBoundsException)"
        )
    }

    // MARK: - @ExperimentalUuidApi annotation

    func testGetUuidHasExperimentalUuidApiAnnotation() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "getUuid"].map { interner.intern($0) }
        let sym = try XCTUnwrap(sema.symbols.lookupAll(fqName: fq).first)
        let annotations = sema.symbols.annotations(for: sym)
        XCTAssertTrue(
            annotations.contains { $0.annotationFQName == "kotlin.uuid.ExperimentalUuidApi" },
            "getUuid must carry @ExperimentalUuidApi annotation"
        )
    }
}
