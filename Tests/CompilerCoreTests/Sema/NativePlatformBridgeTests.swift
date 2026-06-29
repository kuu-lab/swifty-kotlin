#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-NATIVE-PLATFORM-002: Sema-level tests verifying that
/// Platform, OsFamily, CpuArchitecture, and MemoryModel are visible and correctly
/// bridged from a common expect declaration to a native actual declaration.
/// No runtime edits are made; these tests exercise the symbol-table and
/// type-checker layers only.
@Suite
struct NativePlatformBridgeTests {

    // MARK: - OsFamily visibility

    @Test
    func testOsFamilyEnumIsVisibleInSymbolTable() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let fqName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("native"),
            ctx.interner.intern("OsFamily"),
        ]
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName).flatMap { sema.symbols.symbol($0) },
            "kotlin.native.OsFamily must be registered as a synthetic enum class"
        )
        #expect(symbol.kind == .enumClass)
    }

    @Test
    func testOsFamilyHasExpectedEntries() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let baseFQName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("native"),
            ctx.interner.intern("OsFamily"),
        ]
        let expectedEntries = ["UNKNOWN", "MACOSX", "IOS", "TVOS", "WATCHOS",
                               "LINUX", "WINDOWS", "ANDROID", "WASM"]
        for entry in expectedEntries {
            let entryFQName = baseFQName + [ctx.interner.intern(entry)]
            let sym = sema.symbols.lookup(fqName: entryFQName).flatMap { sema.symbols.symbol($0) }
            #expect(sym != nil, "OsFamily.\(entry) must be visible in the symbol table")
        }
    }

    // MARK: - CpuArchitecture visibility

    @Test
    func testCpuArchitectureEnumIsVisibleInSymbolTable() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let fqName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("native"),
            ctx.interner.intern("CpuArchitecture"),
        ]
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName).flatMap { sema.symbols.symbol($0) },
            "kotlin.native.CpuArchitecture must be registered as a synthetic enum class"
        )
        #expect(symbol.kind == .enumClass)
    }

    @Test
    func testCpuArchitectureHasExpectedEntries() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let baseFQName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("native"),
            ctx.interner.intern("CpuArchitecture"),
        ]
        let expectedEntries = ["UNKNOWN", "X86", "X64", "ARM32",
                               "ARM64", "MIPS32", "MIPSEL32", "WASM32"]
        for entry in expectedEntries {
            let entryFQName = baseFQName + [ctx.interner.intern(entry)]
            let sym = sema.symbols.lookup(fqName: entryFQName).flatMap { sema.symbols.symbol($0) }
            #expect(sym != nil, "CpuArchitecture.\(entry) must be visible in the symbol table")
        }
    }

    // MARK: - MemoryModel visibility

    @Test
    func testMemoryModelEnumIsVisibleInSymbolTable() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let fqName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("native"),
            ctx.interner.intern("MemoryModel"),
        ]
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName).flatMap { sema.symbols.symbol($0) },
            "kotlin.native.MemoryModel must be registered as a synthetic enum class"
        )
        #expect(symbol.kind == .enumClass)
    }

    @Test
    func testMemoryModelHasExpectedEntries() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let baseFQName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("native"),
            ctx.interner.intern("MemoryModel"),
        ]
        let expectedEntries = ["STRICT", "RELAXED", "EXPERIMENTAL"]
        for entry in expectedEntries {
            let entryFQName = baseFQName + [ctx.interner.intern(entry)]
            let entrySymbol = try #require(
                sema.symbols.lookup(fqName: entryFQName),
                "MemoryModel.\(entry) must be visible in the symbol table"
            )
            let entryType = try #require(
                sema.symbols.propertyType(for: entrySymbol),
                "MemoryModel.\(entry) must carry the enum type"
            )
            guard case .classType(let classType) = sema.types.kind(of: entryType) else {
                Issue.record("MemoryModel.\(entry) must have a class type")
                continue
            }
            let enumSymbol = try #require(sema.symbols.lookup(fqName: baseFQName))
            #expect(classType.classSymbol == enumSymbol)
        }
    }

    // MARK: - Platform object visibility

    @Test
    func testPlatformObjectIsVisibleInSymbolTable() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let fqName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("native"),
            ctx.interner.intern("Platform"),
        ]
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName).flatMap { sema.symbols.symbol($0) },
            "kotlin.native.Platform must be registered as a synthetic object/class"
        )
        // Platform is registered as a class acting as an object singleton
        #expect(
            symbol.kind == .class || symbol.kind == .object,
            "Expected Platform to be a class or object, got \(symbol.kind)"
        )
    }

    @Test
    func testPlatformOsFamilyPropertyIsVisible() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let fqName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("native"),
            ctx.interner.intern("Platform"),
            ctx.interner.intern("osFamily"),
        ]
        let symbol = sema.symbols.lookup(fqName: fqName).flatMap { sema.symbols.symbol($0) }
        #expect(symbol != nil, "Platform.osFamily must be registered as a property")
        #expect(symbol?.kind == .property)
    }

    @Test
    func testPlatformCpuArchitecturePropertyIsVisible() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let fqName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("native"),
            ctx.interner.intern("Platform"),
            ctx.interner.intern("cpuArchitecture"),
        ]
        let symbol = sema.symbols.lookup(fqName: fqName).flatMap { sema.symbols.symbol($0) }
        #expect(symbol != nil, "Platform.cpuArchitecture must be registered as a property")
        #expect(symbol?.kind == .property)
    }

    @Test
    func testPlatformMemoryModelPropertyIsVisibleAndLinked() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let fqName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("native"),
            ctx.interner.intern("Platform"),
            ctx.interner.intern("memoryModel"),
        ]
        let propertySymbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "Platform.memoryModel must be registered as a property"
        )
        #expect(sema.symbols.symbol(propertySymbol)?.kind == .property)
        #expect(sema.symbols.externalLinkName(for: propertySymbol) == "kk_platform_memoryModel")

        let propertyType = try #require(sema.symbols.propertyType(for: propertySymbol))
        guard case .classType(let classType) = sema.types.kind(of: propertyType) else {
            Issue.record("Platform.memoryModel must have type kotlin.native.MemoryModel")
            return
        }
        let memoryModelSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "native", "MemoryModel"].map { ctx.interner.intern($0) })
        )
        #expect(classType.classSymbol == memoryModelSymbol)
    }

    @Test
    func testPlatformCanAccessUnalignedPropertyIsVisible() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let fqName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("native"),
            ctx.interner.intern("Platform"),
            ctx.interner.intern("canAccessUnaligned"),
        ]
        let symbol = sema.symbols.lookup(fqName: fqName).flatMap { sema.symbols.symbol($0) }
        #expect(symbol != nil, "Platform.canAccessUnaligned must be registered as a property")
        #expect(symbol?.kind == .property)
    }

    @Test
    func testPlatformIsLittleEndianPropertyIsVisible() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let fqName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("native"),
            ctx.interner.intern("Platform"),
            ctx.interner.intern("isLittleEndian"),
        ]
        let symbol = sema.symbols.lookup(fqName: fqName).flatMap { sema.symbols.symbol($0) }
        #expect(symbol != nil, "Platform.isLittleEndian must be registered as a property")
        #expect(symbol?.kind == .property)
    }

    // MARK: - Common → Native expect/actual bridge

    /// Verifies that a top-level expect/actual class named OsFamily (mirroring the
    /// real kotlin.native.OsFamily bridge shape) resolves without errors.
    /// Enum body entries are omitted because the sema treats them as duplicate
    /// declarations when both expect and actual bodies share the same scope;
    /// the class-level expect/actual link is what this test exercises.
    @Test
    func testOsFamilyLikeExpectActualBridgeResolvesCleanly() throws {
        let sources = [
            // common module: expect class (body omitted — entry declarations
            // from both sides would conflict in the shared scope)
            """
            package sample.native
            expect class OsFamily
            """,
            // native module: actual implementation
            """
            package sample.native
            actual class OsFamily
            """,
        ]

        let ctx = makeContextFromSources(sources)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter {
            if case .error = $0.severity { return true }
            return false
        }
        #expect(errors.isEmpty, "Expect/actual OsFamily bridge must not produce errors, got: \(errors)")

        let sema = try #require(ctx.sema)
        let fqName = [
            ctx.interner.intern("sample"),
            ctx.interner.intern("native"),
            ctx.interner.intern("OsFamily"),
        ]
        let allSymbols = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
        let expectSym = try #require(allSymbols.first { $0.flags.contains(.expectDeclaration) })
        let actualSym = try #require(allSymbols.first { $0.flags.contains(.actualDeclaration) })
        #expect(sema.symbols.actualSymbol(for: expectSym.id) == actualSym.id)
    }

    // MARK: - Common → Native expect/actual bridge for CpuArchitecture

    @Test
    func testCpuArchitectureLikeExpectActualBridgeResolvesCleanly() throws {
        let sources = [
            """
            package sample.native
            expect class CpuArchitecture
            """,
            """
            package sample.native
            actual class CpuArchitecture
            """,
        ]

        let ctx = makeContextFromSources(sources)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter {
            if case .error = $0.severity { return true }
            return false
        }
        #expect(errors.isEmpty, "Expect/actual CpuArchitecture bridge must not produce errors, got: \(errors)")

        let sema = try #require(ctx.sema)
        let fqName = [
            ctx.interner.intern("sample"),
            ctx.interner.intern("native"),
            ctx.interner.intern("CpuArchitecture"),
        ]
        let allSymbols = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
        let expectSym = try #require(allSymbols.first { $0.flags.contains(.expectDeclaration) })
        let actualSym = try #require(allSymbols.first { $0.flags.contains(.actualDeclaration) })
        #expect(sema.symbols.actualSymbol(for: expectSym.id) == actualSym.id)
    }

    // MARK: - Common → Native expect/actual bridge for Platform class

    @Test
    func testPlatformLikeExpectActualBridgeResolvesCleanly() throws {
        let sources = [
            // expect: a class named Platform (mirrors the stdlib shape)
            """
            package sample.native
            expect class Platform
            """,
            // actual: same class
            """
            package sample.native
            actual class Platform
            """,
        ]

        let ctx = makeContextFromSources(sources)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter {
            if case .error = $0.severity { return true }
            return false
        }
        #expect(errors.isEmpty, "Expect/actual Platform bridge must not produce errors, got: \(errors)")

        let sema = try #require(ctx.sema)
        let fqName = [
            ctx.interner.intern("sample"),
            ctx.interner.intern("native"),
            ctx.interner.intern("Platform"),
        ]
        let allSymbols = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
        let expectSym = try #require(allSymbols.first { $0.flags.contains(.expectDeclaration) })
        let actualSym = try #require(allSymbols.first { $0.flags.contains(.actualDeclaration) })
        #expect(sema.symbols.actualSymbol(for: expectSym.id) == actualSym.id)
    }

    // MARK: - Common -> Native expect/actual bridge for MemoryModel enum

    @Test
    func testMemoryModelLikeExpectActualBridgeResolvesCleanly() throws {
        let sources = [
            """
            package sample.native
            expect enum class MemoryModel
            """,
            """
            package sample.native
            actual enum class MemoryModel {
                STRICT,
                RELAXED,
                EXPERIMENTAL
            }
            """,
        ]

        let ctx = makeContextFromSources(sources)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter {
            if case .error = $0.severity { return true }
            return false
        }
        #expect(errors.isEmpty, "Expect/actual MemoryModel bridge must not produce errors, got: \(errors)")

        let sema = try #require(ctx.sema)
        let fqName = [
            ctx.interner.intern("sample"),
            ctx.interner.intern("native"),
            ctx.interner.intern("MemoryModel"),
        ]
        let allSymbols = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
        let expectSym = try #require(allSymbols.first { $0.flags.contains(.expectDeclaration) })
        let actualSym = try #require(allSymbols.first { $0.flags.contains(.actualDeclaration) })
        #expect(sema.symbols.actualSymbol(for: expectSym.id) == actualSym.id)
    }

    // MARK: - Mismatch detection

    @Test
    func testExpectEnumActualClassMismatchIsRejected() throws {
        let sources = [
            // expect: enum class
            """
            package sample.native
            expect enum class OsFamily {
                UNKNOWN
            }
            """,
            // actual: plain class — kind mismatch
            """
            package sample.native
            actual class OsFamily
            """,
        ]

        let ctx = makeContextFromSources(sources)
        try runSema(ctx)

        let errorCodes = ctx.diagnostics.diagnostics.compactMap { d -> String? in
            guard d.severity == .error else { return nil }
            return d.code
        }
        #expect(
            errorCodes.contains("KSWIFTK-MPP-UNRESOLVED"),
            "Kind mismatch between expect enum class and actual class must be diagnosed, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
#endif
