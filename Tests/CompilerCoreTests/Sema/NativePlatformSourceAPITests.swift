#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-1211: the complete Platform surface is source-backed and retains its
/// exact Kotlin 2.3.10 member ownership, mutability, and types.
@Suite
struct NativePlatformSourceAPITests {
    @Test
    func testPlatformSourceBackedSurfaceHasExactTypesAndOwnership() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        import kotlin.native.Platform

        fun probe(): Int {
            val unaligned: Boolean = Platform.canAccessUnaligned
            val littleEndian: Boolean = Platform.isLittleEndian
            val debug: Boolean = Platform.isDebugBinary
            val processors: Int = Platform.getAvailableProcessors()
            val programName: String? = Platform.programName
            Platform.isMemoryLeakCheckerActive = !Platform.isMemoryLeakCheckerActive
            return processors + if (unaligned || littleEndian || debug || programName != null) 1 else 0
        }
        """

        var result: CompilationContext?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = ctx
        }

        let ctx = try #require(result)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let platformFQName = ["kotlin", "native", "Platform"].map { interner.intern($0) }
        let platformID = try #require(sema.symbols.lookup(fqName: platformFQName))
        let platform = try #require(sema.symbols.symbol(platformID))
        #expect(platform.kind == .object)
        #expect(sema.symbols.isSourceBackedSymbol(platformID))
        #expect(!platform.flags.contains(.synthetic))

        let platformType = sema.types.make(.classType(ClassType(
            classSymbol: platformID,
            args: [],
            nullability: .nonNull
        )))
        let enumTypes: [String: TypeID] = try ["OsFamily", "CpuArchitecture", "MemoryModel"].reduce(into: [:]) { result, name in
            let enumFQName = ["kotlin", "native", name].map { interner.intern($0) }
            let enumID = try #require(sema.symbols.lookup(fqName: enumFQName))
            result[name] = sema.types.make(.classType(ClassType(
                classSymbol: enumID,
                args: [],
                nullability: .nonNull
            )))
        }

        let expectedProperties: [(String, TypeID, Bool)] = [
            ("canAccessUnaligned", sema.types.booleanType, false),
            ("isLittleEndian", sema.types.booleanType, false),
            ("osFamily", try #require(enumTypes["OsFamily"]), false),
            ("cpuArchitecture", try #require(enumTypes["CpuArchitecture"]), false),
            ("memoryModel", try #require(enumTypes["MemoryModel"]), false),
            ("isDebugBinary", sema.types.booleanType, false),
            ("isFreezingEnabled", sema.types.booleanType, false),
            ("programName", sema.types.make(.stringStruct(.nullable)), false),
            ("isMemoryLeakCheckerActive", sema.types.booleanType, true),
            ("isCleanersLeakCheckerActive", sema.types.booleanType, true),
        ]

        for (name, expectedType, isMutable) in expectedProperties {
            let propertyFQName = platformFQName + [interner.intern(name)]
            let propertyID = try #require(
                sema.symbols.lookup(fqName: propertyFQName),
                "Platform.\(name) must be source-backed"
            )
            let property = try #require(sema.symbols.symbol(propertyID))
            #expect(property.kind == .property)
            #expect(sema.symbols.isSourceBackedSymbol(propertyID))
            #expect(!property.flags.contains(.synthetic))
            #expect(property.flags.contains(.mutable) == isMutable)
            #expect(sema.symbols.propertyType(for: propertyID) == expectedType)
        }

        let functionFQName = platformFQName + [interner.intern("getAvailableProcessors")]
        let functionID = try #require(
            sema.symbols.lookup(fqName: functionFQName),
            "Platform.getAvailableProcessors must be source-backed"
        )
        let function = try #require(sema.symbols.symbol(functionID))
        let signature = try #require(sema.symbols.functionSignature(for: functionID))
        #expect(function.kind == .function)
        #expect(sema.symbols.isSourceBackedSymbol(functionID))
        #expect(!function.flags.contains(.synthetic))
        #expect(signature.receiverType == platformType)
        #expect(signature.parameterTypes.isEmpty)
        #expect(signature.returnType == sema.types.intType)

        let expectedBridgeNames: Set<String> = [
            "kk_platform_canAccessUnaligned",
            "kk_platform_isLittleEndian",
            "kk_platform_osFamily",
            "kk_platform_cpuArchitecture",
            "kk_platform_isDebugBinary",
            "kk_platform_programName",
            "kk_platform_isMemoryLeakCheckerActive_load",
            "kk_platform_isMemoryLeakCheckerActive_store",
            "kk_platform_getAvailableProcessorsEnv",
            "kk_platform_getAvailableProcessors",
        ]
        let actualBridgeNames = Set(sema.symbols.allSymbols().compactMap {
            sema.symbols.externalLinkName(for: $0.id)
        })
        #expect(expectedBridgeNames.isSubset(of: actualBridgeNames))
    }
}
#endif
