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

    @Test
    func testNativePlatformSymbolsAndCleanBridges() throws {
        let sources: [String] = [
            // source 0
            """
            fun noop() {}
            """,
            // source 1
            """

                        package sample0.native
                        expect class OsFamily

            """,
            // source 2
            """

                        package sample0.native
                        actual class OsFamily

            """,
            // source 3
            """

                        package sample1.native
                        expect class CpuArchitecture

            """,
            // source 4
            """

                        package sample1.native
                        actual class CpuArchitecture

            """,
            // source 5
            """

                        package sample2.native
                        expect class Platform

            """,
            // source 6
            """

                        package sample2.native
                        actual class Platform

            """,
            // source 7
            """

                        package sample3.native
                        expect enum class MemoryModel

            """,
            // source 8
            """

                        package sample3.native
                        actual enum class MemoryModel {
                            STRICT,
                            RELAXED,
                            EXPERIMENTAL
                        }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = sema

            // testOsFamilyEnumIsVisibleInSymbolTable
            do {
                let sema = try #require(ctx.sema)
                let fqName = [
                    interner.intern("kotlin"),
                    interner.intern("native"),
                    interner.intern("OsFamily"),
                ]
                let symbol = try #require(
                    sema.symbols.lookup(fqName: fqName).flatMap { sema.symbols.symbol($0) },
                    "kotlin.native.OsFamily must be registered as a synthetic enum class"
                )
                #expect(symbol.kind == .enumClass)
            }

            // testOsFamilyHasExpectedEntries
            do {
                let sema = try #require(ctx.sema)
                let baseFQName = [
                    interner.intern("kotlin"),
                    interner.intern("native"),
                    interner.intern("OsFamily"),
                ]
                let expectedEntries = ["UNKNOWN", "MACOSX", "IOS", "TVOS", "WATCHOS",
                                       "LINUX", "WINDOWS", "ANDROID", "WASM"]
                for entry in expectedEntries {
                    let entryFQName = baseFQName + [interner.intern(entry)]
                    let sym = sema.symbols.lookup(fqName: entryFQName).flatMap { sema.symbols.symbol($0) }
                    #expect(sym != nil, "OsFamily.\(entry) must be visible in the symbol table")
                }
            }

            // testCpuArchitectureEnumIsVisibleInSymbolTable
            do {
                let sema = try #require(ctx.sema)
                let fqName = [
                    interner.intern("kotlin"),
                    interner.intern("native"),
                    interner.intern("CpuArchitecture"),
                ]
                let symbol = try #require(
                    sema.symbols.lookup(fqName: fqName).flatMap { sema.symbols.symbol($0) },
                    "kotlin.native.CpuArchitecture must be registered as a synthetic enum class"
                )
                #expect(symbol.kind == .enumClass)
            }

            // testCpuArchitectureHasExpectedEntries
            do {
                let sema = try #require(ctx.sema)
                let baseFQName = [
                    interner.intern("kotlin"),
                    interner.intern("native"),
                    interner.intern("CpuArchitecture"),
                ]
                let expectedEntries = ["UNKNOWN", "X86", "X64", "ARM32",
                                       "ARM64", "MIPS32", "MIPSEL32", "WASM32"]
                for entry in expectedEntries {
                    let entryFQName = baseFQName + [interner.intern(entry)]
                    let sym = sema.symbols.lookup(fqName: entryFQName).flatMap { sema.symbols.symbol($0) }
                    #expect(sym != nil, "CpuArchitecture.\(entry) must be visible in the symbol table")
                }
            }

            // testMemoryModelEnumIsVisibleInSymbolTable
            do {
                let sema = try #require(ctx.sema)
                let fqName = [
                    interner.intern("kotlin"),
                    interner.intern("native"),
                    interner.intern("MemoryModel"),
                ]
                let symbol = try #require(
                    sema.symbols.lookup(fqName: fqName).flatMap { sema.symbols.symbol($0) },
                    "kotlin.native.MemoryModel must be registered as a synthetic enum class"
                )
                #expect(symbol.kind == .enumClass)
            }

            // testMemoryModelHasExpectedEntries
            do {
                let sema = try #require(ctx.sema)
                let baseFQName = [
                    interner.intern("kotlin"),
                    interner.intern("native"),
                    interner.intern("MemoryModel"),
                ]
                let expectedEntries = ["STRICT", "RELAXED", "EXPERIMENTAL"]
                for entry in expectedEntries {
                    let entryFQName = baseFQName + [interner.intern(entry)]
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

            // testPlatformObjectIsVisibleInSymbolTable
            do {
                let sema = try #require(ctx.sema)
                let fqName = [
                    interner.intern("kotlin"),
                    interner.intern("native"),
                    interner.intern("Platform"),
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

            // testPlatformOsFamilyPropertyIsVisible
            do {
                let sema = try #require(ctx.sema)
                let fqName = [
                    interner.intern("kotlin"),
                    interner.intern("native"),
                    interner.intern("Platform"),
                    interner.intern("osFamily"),
                ]
                let symbol = sema.symbols.lookup(fqName: fqName).flatMap { sema.symbols.symbol($0) }
                #expect(symbol != nil, "Platform.osFamily must be registered as a property")
                #expect(symbol?.kind == .property)
            }

            // testPlatformCpuArchitecturePropertyIsVisible
            do {
                let sema = try #require(ctx.sema)
                let fqName = [
                    interner.intern("kotlin"),
                    interner.intern("native"),
                    interner.intern("Platform"),
                    interner.intern("cpuArchitecture"),
                ]
                let symbol = sema.symbols.lookup(fqName: fqName).flatMap { sema.symbols.symbol($0) }
                #expect(symbol != nil, "Platform.cpuArchitecture must be registered as a property")
                #expect(symbol?.kind == .property)
            }

            // testPlatformMemoryModelPropertyIsVisibleAndLinked
            do {
                let sema = try #require(ctx.sema)
                let fqName = [
                    interner.intern("kotlin"),
                    interner.intern("native"),
                    interner.intern("Platform"),
                    interner.intern("memoryModel"),
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
                    sema.symbols.lookup(fqName: ["kotlin", "native", "MemoryModel"].map { interner.intern($0) })
                )
                #expect(classType.classSymbol == memoryModelSymbol)
            }

            // testPlatformCanAccessUnalignedPropertyIsVisible
            do {
                let sema = try #require(ctx.sema)
                let fqName = [
                    interner.intern("kotlin"),
                    interner.intern("native"),
                    interner.intern("Platform"),
                    interner.intern("canAccessUnaligned"),
                ]
                let symbol = sema.symbols.lookup(fqName: fqName).flatMap { sema.symbols.symbol($0) }
                #expect(symbol != nil, "Platform.canAccessUnaligned must be registered as a property")
                #expect(symbol?.kind == .property)
            }

            // testPlatformIsLittleEndianPropertyIsVisible
            do {
                let sema = try #require(ctx.sema)
                let fqName = [
                    interner.intern("kotlin"),
                    interner.intern("native"),
                    interner.intern("Platform"),
                    interner.intern("isLittleEndian"),
                ]
                let symbol = sema.symbols.lookup(fqName: fqName).flatMap { sema.symbols.symbol($0) }
                #expect(symbol != nil, "Platform.isLittleEndian must be registered as a property")
                #expect(symbol?.kind == .property)
            }

            // testOsFamilyLikeExpectActualBridgeResolvesCleanly
            do {
                let samplePackage = "sample0"
                _ = samplePackage
                let errors = ctx.diagnostics.diagnostics.filter {
                    if case .error = $0.severity { return true }
                    return false
                }
                #expect(errors.isEmpty, "Expect/actual OsFamily bridge must not produce errors, got: \(errors)")

                let sema = try #require(ctx.sema)
                let fqName = [
                    interner.intern(samplePackage),
                    interner.intern("native"),
                    interner.intern("OsFamily"),
                ]
                let allSymbols = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
                let expectSym = try #require(allSymbols.first { $0.flags.contains(.expectDeclaration) })
                let actualSym = try #require(allSymbols.first { $0.flags.contains(.actualDeclaration) })
                #expect(sema.symbols.actualSymbol(for: expectSym.id) == actualSym.id)
            }

            // testCpuArchitectureLikeExpectActualBridgeResolvesCleanly
            do {
                let samplePackage = "sample1"
                _ = samplePackage
                let errors = ctx.diagnostics.diagnostics.filter {
                    if case .error = $0.severity { return true }
                    return false
                }
                #expect(errors.isEmpty, "Expect/actual CpuArchitecture bridge must not produce errors, got: \(errors)")

                let sema = try #require(ctx.sema)
                let fqName = [
                    interner.intern(samplePackage),
                    interner.intern("native"),
                    interner.intern("CpuArchitecture"),
                ]
                let allSymbols = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
                let expectSym = try #require(allSymbols.first { $0.flags.contains(.expectDeclaration) })
                let actualSym = try #require(allSymbols.first { $0.flags.contains(.actualDeclaration) })
                #expect(sema.symbols.actualSymbol(for: expectSym.id) == actualSym.id)
            }

            // testPlatformLikeExpectActualBridgeResolvesCleanly
            do {
                let samplePackage = "sample2"
                _ = samplePackage
                let errors = ctx.diagnostics.diagnostics.filter {
                    if case .error = $0.severity { return true }
                    return false
                }
                #expect(errors.isEmpty, "Expect/actual Platform bridge must not produce errors, got: \(errors)")

                let sema = try #require(ctx.sema)
                let fqName = [
                    interner.intern(samplePackage),
                    interner.intern("native"),
                    interner.intern("Platform"),
                ]
                let allSymbols = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
                let expectSym = try #require(allSymbols.first { $0.flags.contains(.expectDeclaration) })
                let actualSym = try #require(allSymbols.first { $0.flags.contains(.actualDeclaration) })
                #expect(sema.symbols.actualSymbol(for: expectSym.id) == actualSym.id)
            }

            // testMemoryModelLikeExpectActualBridgeResolvesCleanly
            do {
                let samplePackage = "sample3"
                _ = samplePackage
                let errors = ctx.diagnostics.diagnostics.filter {
                    if case .error = $0.severity { return true }
                    return false
                }
                #expect(errors.isEmpty, "Expect/actual MemoryModel bridge must not produce errors, got: \(errors)")

                let sema = try #require(ctx.sema)
                let fqName = [
                    interner.intern(samplePackage),
                    interner.intern("native"),
                    interner.intern("MemoryModel"),
                ]
                let allSymbols = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
                let expectSym = try #require(allSymbols.first { $0.flags.contains(.expectDeclaration) })
                let actualSym = try #require(allSymbols.first { $0.flags.contains(.actualDeclaration) })
                #expect(sema.symbols.actualSymbol(for: expectSym.id) == actualSym.id)
            }
        }
    }

    @Test
    func testExpectEnumActualClassMismatchIsRejected() throws {
        let sources: [String] = [
            // source 0
            """

                        package sample0.native
                        expect enum class OsFamily {
                            UNKNOWN
                        }

            """,
            // source 1
            """

                        package sample0.native
                        actual class OsFamily

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = sema

            // testExpectEnumActualClassMismatchIsRejected
            do {
                let samplePackage = "sample0"
                _ = samplePackage
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
    }
}
#endif
