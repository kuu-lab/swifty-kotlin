#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension LibraryMetadataCacheBehaviorTests {
    @Test
    func testManifestCacheHitOnSameKey() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
        let manifestJSON = """
        { "formatVersion": 1, "moduleName": "A1", "metadata": "metadata.bin" }
        """
        try manifestJSON.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "symbols=0".write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let cache = LibraryMetadataCache()
        let info = DataFlowSemaPhase.LibraryManifestInfo(metadataPath: libDir.appendingPathComponent("metadata.bin").path, inlineKIRDir: nil, moduleName: "TestMod", isValid: true)
        let target = TargetTriple.hostDefault()
        cache.cacheManifestInfo(info, libraryDir: libDir.path, target: target)

        let retrieved = cache.cachedManifestInfo(libraryDir: libDir.path, target: target)
        #expect(retrieved != nil, "Should hit cache for same libraryDir + mtime + target")
        #expect(retrieved?.metadataPath == info.metadataPath)
        #expect(retrieved?.isValid == true)
    }

    /// A2: Manifest cache miss — different libraryDir
    @Test
    func testManifestCacheMissOnDifferentLibraryDir() throws {
        let fm = FileManager.default
        let baseDir1 = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir1 = baseDir1.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir1, withIntermediateDirectories: true)
        try "{}".write(to: libDir1.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        let baseDir2 = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir2 = baseDir2.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir2, withIntermediateDirectories: true)
        try "{}".write(to: libDir2.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        let cache = LibraryMetadataCache()
        let info = DataFlowSemaPhase.LibraryManifestInfo(metadataPath: "/some/path", inlineKIRDir: nil, moduleName: "TestMod", isValid: true)
        let target = TargetTriple.hostDefault()
        cache.cacheManifestInfo(info, libraryDir: libDir1.path, target: target)

        let retrieved = cache.cachedManifestInfo(libraryDir: libDir2.path, target: target)
        #expect(retrieved == nil, "Should miss cache for different libraryDir")
    }

    /// A3: Manifest cache miss — mtime changed (file modified)
    @Test
    func testManifestCacheMissOnMtimeChange() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
        let manifestPath = libDir.appendingPathComponent("manifest.json")
        try "{}".write(to: manifestPath, atomically: true, encoding: .utf8)

        let cache = LibraryMetadataCache()
        let info = DataFlowSemaPhase.LibraryManifestInfo(metadataPath: "/some/path", inlineKIRDir: nil, moduleName: "TestMod", isValid: true)
        let target = TargetTriple.hostDefault()
        cache.cacheManifestInfo(info, libraryDir: libDir.path, target: target)

        // Verify hit before modification
        #expect(cache.cachedManifestInfo(libraryDir: libDir.path, target: target) != nil, "Should hit before modification")

        // Explicitly set a different mtime to deterministically invalidate the cache
        // (avoids relying on filesystem mtime granularity which can be 1s on some systems)
        let futureDate = Date(timeIntervalSinceNow: 10)
        try fm.setAttributes([.modificationDate: futureDate], ofItemAtPath: manifestPath.path)

        let retrieved = cache.cachedManifestInfo(libraryDir: libDir.path, target: target)
        #expect(retrieved == nil, "Should miss cache after file modification changes mtime")
    }

    /// A4: Metadata cache hit — same interner, same path+mtime
    @Test
    func testMetadataCacheHitWithSameInterner() throws {
        let fm = FileManager.default
        let metadataPath = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bin").path
        try "symbols=0".write(toFile: metadataPath, atomically: true, encoding: .utf8)

        let cache = LibraryMetadataCache()
        let interner = StringInterner()
        let record = DataFlowSemaPhase.ImportedLibrarySymbolRecord(
            kind: .function, mangledName: "", fqName: [interner.intern("test")],
            arity: 0, isSuspend: false, isInline: false, typeSignature: nil,
            externalLinkName: nil, declaredFieldCount: nil, declaredInstanceSizeWords: nil,
            declaredVtableSize: nil, declaredItableSize: nil, superFQName: nil,
            fieldOffsets: [], vtableSlots: [], itableSlots: [], isDataClass: false,
            isSealedClass: false, isValueClass: false,
            isExpect: false, isActual: false,
            valueClassUnderlyingTypeSig: nil, annotations: [], sealedSubclassFQNames: []
        )
        cache.cacheMetadataRecords([record], metadataPath: metadataPath, interner: interner)

        let retrieved = cache.cachedMetadataRecords(metadataPath: metadataPath, interner: interner)
        #expect(retrieved != nil, "Should hit cache with same interner")
        #expect(retrieved?.count == 1)
    }

    /// A5: Metadata cache miss — different interner
    @Test
    func testMetadataCacheMissWithDifferentInterner() throws {
        let fm = FileManager.default
        let metadataPath = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bin").path
        try "symbols=0".write(toFile: metadataPath, atomically: true, encoding: .utf8)

        let cache = LibraryMetadataCache()
        let interner1 = StringInterner()
        let record = DataFlowSemaPhase.ImportedLibrarySymbolRecord(
            kind: .function, mangledName: "", fqName: [interner1.intern("test")],
            arity: 0, isSuspend: false, isInline: false, typeSignature: nil,
            externalLinkName: nil, declaredFieldCount: nil, declaredInstanceSizeWords: nil,
            declaredVtableSize: nil, declaredItableSize: nil, superFQName: nil,
            fieldOffsets: [], vtableSlots: [], itableSlots: [], isDataClass: false,
            isSealedClass: false, isValueClass: false,
            isExpect: false, isActual: false,
            valueClassUnderlyingTypeSig: nil, annotations: [], sealedSubclassFQNames: []
        )
        cache.cacheMetadataRecords([record], metadataPath: metadataPath, interner: interner1)

        let interner2 = StringInterner()
        let retrieved = cache.cachedMetadataRecords(metadataPath: metadataPath, interner: interner2)
        #expect(retrieved == nil, "Should miss cache with different interner instance")
    }

    /// A6: Signature cache hit — same TypeSystem + SymbolTable
    @Test
    func testSignatureCacheHitWithSameTypeSystemAndSymbolTable() throws {
        let cache = LibraryMetadataCache()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let intType = types.make(.primitive(.int, .nonNull))
        cache.cacheSignature(intType, for: "I", types: types, symbols: symbols)

        let retrieved = cache.cachedSignature("I", types: types, symbols: symbols)
        #expect(retrieved != nil, "Outer optional should be non-nil (cache hit)")
        #expect(try #require(retrieved) == intType, "Should return the cached TypeID")
    }

    /// A7: Signature cache miss — different TypeSystem
    @Test
    func testSignatureCacheMissWithDifferentTypeSystem() {
        let cache = LibraryMetadataCache()
        let types1 = TypeSystem()
        let symbols = SymbolTable()

        let intType = types1.make(.primitive(.int, .nonNull))
        cache.cacheSignature(intType, for: "I", types: types1, symbols: symbols)

        let types2 = TypeSystem()
        let retrieved = cache.cachedSignature("I", types: types2, symbols: symbols)
        #expect(retrieved == nil, "Should miss cache with different TypeSystem")
    }

    /// A8: Signature cache miss — different SymbolTable
    @Test
    func testSignatureCacheMissWithDifferentSymbolTable() {
        let cache = LibraryMetadataCache()
        let types = TypeSystem()
        let symbols1 = SymbolTable()

        let intType = types.make(.primitive(.int, .nonNull))
        cache.cacheSignature(intType, for: "I", types: types, symbols: symbols1)

        let symbols2 = SymbolTable()
        let retrieved = cache.cachedSignature("I", types: types, symbols: symbols2)
        #expect(retrieved == nil, "Should miss cache with different SymbolTable")
    }

    /// A9: Signature cache correctly caches nil (failed parse)
    @Test
    func testSignatureCacheCachesNilForFailedParse() throws {
        let cache = LibraryMetadataCache()
        let types = TypeSystem()
        let symbols = SymbolTable()

        cache.cacheSignature(nil, for: "INVALID", types: types, symbols: symbols)

        let retrieved = cache.cachedSignature("INVALID", types: types, symbols: symbols)
        // Outer optional should be non-nil (cache hit), inner should be nil (cached failure)
        #expect(retrieved != nil, "Outer optional should be non-nil (cache hit for nil value)")
        #expect(try #require(retrieved) == nil, "Inner value should be nil (cached failed parse)")
        #expect(cache.signatureCacheCount == 1)
    }

    /// A10: Signature cache auto-clears on TypeSystem change
    @Test
    func testSignatureCacheAutoClearsOnTypeSystemChange() {
        let cache = LibraryMetadataCache()
        let types1 = TypeSystem()
        let symbols = SymbolTable()

        let intType1 = types1.make(.primitive(.int, .nonNull))
        cache.cacheSignature(intType1, for: "I", types: types1, symbols: symbols)
        cache.cacheSignature(intType1, for: "J", types: types1, symbols: symbols)
        #expect(cache.signatureCacheCount == 2)

        // Switch to new TypeSystem — old entries should be cleared
        let types2 = TypeSystem()
        let intType2 = types2.make(.primitive(.int, .nonNull))
        cache.cacheSignature(intType2, for: "I", types: types2, symbols: symbols)
        #expect(cache.signatureCacheCount == 1, "Old entries should have been cleared")
    }

    /// A11: Metadata cache auto-clears on interner change
    @Test
    func testMetadataCacheAutoClearsOnInternerChange() throws {
        let fm = FileManager.default
        let metadataPath = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bin").path
        try "symbols=0".write(toFile: metadataPath, atomically: true, encoding: .utf8)

        let cache = LibraryMetadataCache()
        let interner1 = StringInterner()
        let record = DataFlowSemaPhase.ImportedLibrarySymbolRecord(
            kind: .function, mangledName: "", fqName: [interner1.intern("test")],
            arity: 0, isSuspend: false, isInline: false, typeSignature: nil,
            externalLinkName: nil, declaredFieldCount: nil, declaredInstanceSizeWords: nil,
            declaredVtableSize: nil, declaredItableSize: nil, superFQName: nil,
            fieldOffsets: [], vtableSlots: [], itableSlots: [], isDataClass: false,
            isSealedClass: false, isValueClass: false,
            isExpect: false, isActual: false,
            valueClassUnderlyingTypeSig: nil, annotations: [], sealedSubclassFQNames: []
        )
        cache.cacheMetadataRecords([record], metadataPath: metadataPath, interner: interner1)
        #expect(cache.metadataCacheCount == 1)

        // Switch to new interner — old entries should be cleared on next store
        let interner2 = StringInterner()
        let record2 = DataFlowSemaPhase.ImportedLibrarySymbolRecord(
            kind: .property, mangledName: "", fqName: [interner2.intern("test2")],
            arity: 0, isSuspend: false, isInline: false, typeSignature: nil,
            externalLinkName: nil, declaredFieldCount: nil, declaredInstanceSizeWords: nil,
            declaredVtableSize: nil, declaredItableSize: nil, superFQName: nil,
            fieldOffsets: [], vtableSlots: [], itableSlots: [], isDataClass: false,
            isSealedClass: false, isValueClass: false,
            isExpect: false, isActual: false,
            valueClassUnderlyingTypeSig: nil, annotations: [], sealedSubclassFQNames: []
        )
        let otherPath = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bin").path
        try "symbols=0".write(toFile: otherPath, atomically: true, encoding: .utf8)
        cache.cacheMetadataRecords([record2], metadataPath: otherPath, interner: interner2)
        #expect(cache.metadataCacheCount == 1, "Old interner entries should have been cleared")
    }

    // --- B. Integration tests (loadImportedLibrarySymbols with cache) ---

    // B1: cache=nil produces identical results to without cache (no regression)
}
#endif
