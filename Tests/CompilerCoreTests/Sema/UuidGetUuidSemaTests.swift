@testable import CompilerCore
import Foundation
import Testing

// KSP-476: ByteArray.getUuid(offset: Int) is pure Kotlin now, declared for
// real in Stdlib/kotlin/uuid/Uuid.kt (no externalLinkName of its own). Verify
// it's source-backed with the expected receiver/parameter/return signature
// and @ExperimentalUuidApi annotation.

@Suite
struct UuidGetUuidSemaTests {

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

    // MARK: - Registration presence

    @Test
    func testGetUuidIsRegisteredInKotlinUuidPackage() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "getUuid"].map { interner.intern($0) }
        #expect(
            !sema.symbols.lookupAll(fqName: fq).isEmpty,
            "ByteArray.getUuid must be registered in kotlin.uuid package"
        )
    }

    // MARK: - Source-backed, not a synthetic stub

    @Test
    func testGetUuidIsSourceBackedNotSynthetic() throws {
        let (ctx, sema, interner) = try makeSemaWithContext()
        let uuidSourceFileID = ctx.sourceManager.fileID(forPath: "__bundled_kotlin/uuid/Uuid.kt")
        let fq = ["kotlin", "uuid", "getUuid"].map { interner.intern($0) }
        #expect(
            sema.symbols.lookupAll(fqName: fq).contains { sym in
                guard let info = sema.symbols.symbol(sym) else { return false }
                return !info.flags.contains(.synthetic) && sema.symbols.sourceFileID(for: sym) == uuidSourceFileID
            },
            "getUuid must be declared in Uuid.kt, not registered as a synthetic stub"
        )
    }

    // MARK: - Receiver type

    @Test
    func testGetUuidHasByteArrayReceiverType() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "getUuid"].map { interner.intern($0) }
        let sym = try #require(sema.symbols.lookupAll(fqName: fq).first)
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            Issue.record("getUuid has no signature"); return
        }
        guard let receiverType = sig.receiverType else {
            Issue.record("getUuid must have a receiver type (ByteArray)"); return
        }
        let byteArrayFQ = ["kotlin", "ByteArray"].map { interner.intern($0) }
        guard let byteArraySym = sema.symbols.lookup(fqName: byteArrayFQ) else {
            Issue.record("kotlin.ByteArray class symbol missing"); return
        }
        if case .classType(let ct) = sema.types.kind(of: receiverType) {
            #expect(ct.classSymbol == byteArraySym, "getUuid receiver must be kotlin.ByteArray")
        } else {
            Issue.record("getUuid receiver type is not a class type; got \(sema.types.kind(of: receiverType))")
        }
    }

    // MARK: - Parameters

    @Test
    func testGetUuidHasOneIntParameter() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "getUuid"].map { interner.intern($0) }
        let sym = try #require(sema.symbols.lookupAll(fqName: fq).first)
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            Issue.record("getUuid has no signature"); return
        }
        #expect(sig.parameterTypes.count == 1, "getUuid must accept exactly one parameter (offset: Int)")
        #expect(sig.parameterTypes.first == sema.types.intType, "offset parameter must be Int")
    }

    // MARK: - Return type

    @Test
    func testGetUuidReturnsUuid() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "getUuid"].map { interner.intern($0) }
        let sym = try #require(sema.symbols.lookupAll(fqName: fq).first)
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            Issue.record("getUuid has no signature"); return
        }
        let uuidFQ = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        guard let uuidSym = sema.symbols.lookup(fqName: uuidFQ) else {
            Issue.record("kotlin.uuid.Uuid class symbol missing"); return
        }
        if case .classType(let ct) = sema.types.kind(of: sig.returnType) {
            #expect(ct.classSymbol == uuidSym, "getUuid return type must be kotlin.uuid.Uuid")
        } else {
            Issue.record("getUuid return type is not a class type; got \(sema.types.kind(of: sig.returnType))")
        }
    }

    // MARK: - @ExperimentalUuidApi annotation

    @Test
    func testGetUuidHasExperimentalUuidApiAnnotation() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "getUuid"].map { interner.intern($0) }
        let sym = try #require(sema.symbols.lookupAll(fqName: fq).first)
        let annotations = sema.symbols.annotations(for: sym)
        #expect(
            annotations.contains { $0.annotationFQName == "kotlin.uuid.ExperimentalUuidApi" },
            "getUuid must carry @ExperimentalUuidApi annotation"
        )
    }
}
