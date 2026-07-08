@testable import CompilerCore
import Foundation
import Testing

// MARK: - STDLIB-UUID-001 / STDLIB-UUID-002 / KSP-476: kotlin.uuid.Uuid API surface inventory
//
// This file catalogues the Uuid-related symbols and verifies that:
//   • the kotlin.uuid package hierarchy is present after sema
//   • Uuid class, Companion object, and all factory/instance members are
//     declared for real in Stdlib/kotlin/uuid/Uuid.kt (not synthetic stubs)
//   • Uuid.random() return type resolves to kotlin.uuid.Uuid
//   • toByteArray() and toLongs() are present with their signatures
//   • @ExperimentalUuidApi opt-in marker: synthesised (STDLIB-EXPERIMENTAL-ABI-001)
//
// KSP-476: parsing/formatting/version/variant/NIL/LEXICAL_ORDER/toLongs/toByteArray/
// fromByteArray/ByteArray extensions are pure Kotlin now, built on top of six
// native bridges (random/fromLongs/mostSignificantBits/leastSignificantBits/
// nameUUIDFromBytes/toKotlinUuid, all `__kk_uuid_*`). None of the *public*
// Uuid API symbols carry an externalLinkName anymore — only the private
// bridge declarations inside Uuid.kt do — so this file checks "declared in
// Uuid.kt, not synthetic" instead of exact link names.
//
// Scope: sema / symbol-table level only. Runtime correctness for the six
// surviving bridges is in RuntimeUuid* tests; pure-Kotlin behavior is
// exercised via Scripts/diff_cases/uuid_basic.kt and uuid_put_uuid.kt.

@Suite
struct UuidAPISurfaceInventoryTests {

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

    // MARK: - Lookup helpers

    private func symbols(
        fqPath: [String],
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        sema.symbols.lookupAll(fqName: fqPath.map { interner.intern($0) })
    }

    private func hasExperimentalUuidApiAnnotation(
        _ symbol: SymbolID,
        sema: SemaModule
    ) -> Bool {
        sema.symbols.annotations(for: symbol).contains {
            $0.annotationFQName == "kotlin.uuid.ExperimentalUuidApi"
        }
    }

    /// True if any symbol at `fqPath` is declared for real in bundled Uuid.kt
    /// (not a synthetic stub registered from Swift).
    private func isSourceBacked(
        fqPath: [String],
        ctx: CompilationContext,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let uuidSourceFileID = ctx.sourceManager.fileID(forPath: "__bundled_kotlin/uuid/Uuid.kt")
        return symbols(fqPath: fqPath, sema: sema, interner: interner).contains { sym in
            guard let info = sema.symbols.symbol(sym) else { return false }
            return !info.flags.contains(.synthetic) && sema.symbols.sourceFileID(for: sym) == uuidSourceFileID
        }
    }

    private func runUuidSemaCollectingDiagnostics(
        _ source: String,
        frontendFlags: [String] = []
    ) -> CompilationContext {
        let fakePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [fakePath], frontendFlags: frontendFlags)
        _ = ctx.sourceManager.addFile(path: fakePath, contents: Data(source.utf8))
        do {
            try runSema(ctx)
        } catch {
            // Individual tests assert on the resulting diagnostics.
        }
        return ctx
    }

    private func optInDiagnostics(in ctx: CompilationContext) -> [Diagnostic] {
        ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
    }

    private func isError(_ diagnostic: Diagnostic) -> Bool {
        if case .error = diagnostic.severity {
            return true
        }
        return false
    }

    // MARK: - 1. Package hierarchy and class registration

    @Test
    func testKotlinUuidPackageIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid"].map { interner.intern($0) }
        #expect(
            sema.symbols.lookup(fqName: fq) != nil,
            "kotlin.uuid package must be present in symbol table after sema"
        )
    }

    @Test
    func testUuidClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        let sym = sema.symbols.lookup(fqName: fq)
        #expect(sym != nil, "kotlin.uuid.Uuid class must be present in symbol table after sema")
    }

    @Test
    func testUuidClassKindIsClass() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: fq),
              let info = sema.symbols.symbol(sym) else {
            Issue.record("kotlin.uuid.Uuid not found"); return
        }
        #expect(info.kind == .class, "kotlin.uuid.Uuid must be registered with kind=class")
    }

    @Test
    func testUuidKotlinSourceIsBundledIntoFrontend() throws {
        let (ctx, _, _) = try makeSemaWithContext()
        #expect(
            ctx.sourceManager.fileID(forPath: "__bundled_kotlin/uuid/Uuid.kt") != nil,
            "KSP-476 requires Stdlib/kotlin/uuid/Uuid.kt to be bundled"
        )
    }

    @Test
    func testUuidClassAPISymbolsComeFromKotlinSource() throws {
        let (ctx, sema, interner) = try makeSemaWithContext()
        let uuidSourceFileID = try #require(
            ctx.sourceManager.fileID(forPath: "__bundled_kotlin/uuid/Uuid.kt")
        )
        let migratedAPIs: [[String]] = [
            ["kotlin", "uuid", "Uuid", "Companion", "random"],
            ["kotlin", "uuid", "Uuid", "Companion", "parse"],
            ["kotlin", "uuid", "Uuid", "Companion", "parseOrNull"],
            ["kotlin", "uuid", "Uuid", "Companion", "parseHex"],
            ["kotlin", "uuid", "Uuid", "Companion", "parseHexOrNull"],
            ["kotlin", "uuid", "Uuid", "Companion", "parseHexDash"],
            ["kotlin", "uuid", "Uuid", "Companion", "parseHexDashOrNull"],
            ["kotlin", "uuid", "Uuid", "Companion", "fromLongs"],
            ["kotlin", "uuid", "Uuid", "Companion", "fromByteArray"],
            ["kotlin", "uuid", "Uuid", "Companion", "nameUUIDFromBytes"],
            ["kotlin", "uuid", "Uuid", "toString"],
            ["kotlin", "uuid", "Uuid", "toHexString"],
            ["kotlin", "uuid", "Uuid", "toLongs"],
            ["kotlin", "uuid", "Uuid", "toByteArray"],
            ["kotlin", "uuid", "Uuid", "version"],
            ["kotlin", "uuid", "Uuid", "variant"],
        ]

        for fqPath in migratedAPIs {
            let symbol = try #require(
                symbols(fqPath: fqPath, sema: sema, interner: interner).first,
                "\(fqPath.joined(separator: ".")) must be registered"
            )
            let info = try #require(sema.symbols.symbol(symbol))
            #expect(
                sema.symbols.sourceFileID(for: symbol) == uuidSourceFileID,
                "\(fqPath.joined(separator: ".")) must be declared by Uuid.kt"
            )
            #expect(
                !info.flags.contains(.synthetic),
                "\(fqPath.joined(separator: ".")) must be source-backed, not synthetic"
            )
        }
    }

    @Test
    func testUuidCompanionObjectIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion"].map { interner.intern($0) }
        #expect(
            sema.symbols.lookup(fqName: fq) != nil,
            "kotlin.uuid.Uuid.Companion object must be registered in symbol table"
        )
    }

    @Test
    func testUuidCompanionHasNoSplitOrDuplicateSymbols() throws {
        let (ctx, sema, interner) = try makeSemaWithContext()
        let uuidSourceFileID = try #require(
            ctx.sourceManager.fileID(forPath: "__bundled_kotlin/uuid/Uuid.kt")
        )
        let uuidFQ = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        let companionFQ = uuidFQ + [interner.intern("Companion")]
        let uuidSymbol = try #require(sema.symbols.lookup(fqName: uuidFQ))
        let companionSymbol = try #require(sema.symbols.companionObjectSymbol(for: uuidSymbol))
        let companionInfo = try #require(sema.symbols.symbol(companionSymbol))

        #expect(
            sema.symbols.lookupAll(fqName: companionFQ) == [companionSymbol],
            "Uuid.Companion must not have split synthetic/source symbols"
        )
        #expect(companionInfo.kind == .object)
        #expect(!companionInfo.flags.contains(.synthetic))
        #expect(sema.symbols.sourceFileID(for: companionSymbol) == uuidSourceFileID)

        for memberName in ["random", "parse", "parseOrNull", "parseHex", "NIL", "LEXICAL_ORDER"] {
            let memberFQ = companionFQ + [interner.intern(memberName)]
            let memberSymbols = sema.symbols.lookupAll(fqName: memberFQ)
            #expect(!memberSymbols.isEmpty, "Uuid.Companion.\(memberName) must be registered")
            for memberSymbol in memberSymbols {
                #expect(
                    sema.symbols.parentSymbol(for: memberSymbol) == companionSymbol,
                    "Uuid.Companion.\(memberName) must share the unified companion parent"
                )
            }
        }
    }

    // MARK: - 2. Companion factory methods

    @Test
    func testUuidRandomCompanionMethodIsSourceBacked() throws {
        let (ctx, sema, interner) = try makeSemaWithContext()
        #expect(
            isSourceBacked(
                fqPath: ["kotlin", "uuid", "Uuid", "Companion", "random"],
                ctx: ctx,
                sema: sema,
                interner: interner
            ),
            "Uuid.random() must be declared in Uuid.kt"
        )
    }

    @Test
    func testUuidRandomReturnTypeIsUuid() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "random"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        #expect(!syms.isEmpty, "Uuid.random() must be in symbol table")
        let randomSym = try #require(syms.first)
        guard let sig = sema.symbols.functionSignature(for: randomSym) else {
            Issue.record("Uuid.random() has no function signature"); return
        }
        // The return type must not be Any/void — it must resolve to Uuid's class type.
        let uuidFQ = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        guard let uuidSym = sema.symbols.lookup(fqName: uuidFQ) else {
            Issue.record("kotlin.uuid.Uuid class symbol missing"); return
        }
        let returnTypeKind = sema.types.kind(of: sig.returnType)
        if case .classType(let ct) = returnTypeKind {
            #expect(
                ct.classSymbol == uuidSym,
                "Uuid.random() return type must be kotlin.uuid.Uuid"
            )
        } else {
            Issue.record("Uuid.random() return type is not a class type; got \(returnTypeKind)")
        }
    }

    @Test
    func testUuidParseCompanionMethodIsSourceBacked() throws {
        let (ctx, sema, interner) = try makeSemaWithContext()
        #expect(
            isSourceBacked(
                fqPath: ["kotlin", "uuid", "Uuid", "Companion", "parse"],
                ctx: ctx,
                sema: sema,
                interner: interner
            ),
            "Uuid.parse(uuidString) must be declared in Uuid.kt"
        )
    }

    @Test
    func testUuidParseAcceptsStringParameter() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "parse"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        #expect(!syms.isEmpty, "Uuid.parse must be registered")
        let parseSym = try #require(syms.first)
        guard let sig = sema.symbols.functionSignature(for: parseSym) else {
            Issue.record("Uuid.parse has no signature"); return
        }
        #expect(sig.parameterTypes.count == 1, "Uuid.parse must take exactly 1 parameter")
        // String is a primitive type in the compiler's TypeSystem (stringType).
        // Verify the parameter resolves to the compiler's string type.
        #expect(
            sig.parameterTypes[0] == sema.types.stringType,
            "Uuid.parse parameter must be of type String (sema.types.stringType)"
        )
    }

    @Test
    func testUuidParseOrNullAcceptsStringParameterAndReturnsNullableUuid() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "parseOrNull"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        #expect(!syms.isEmpty, "Uuid.parseOrNull must be registered")
        let parseOrNullSym = try #require(syms.first)
        guard let sig = sema.symbols.functionSignature(for: parseOrNullSym) else {
            Issue.record("Uuid.parseOrNull has no signature"); return
        }
        #expect(sig.parameterTypes.count == 1, "Uuid.parseOrNull must take exactly 1 parameter")
        #expect(
            sig.parameterTypes[0] == sema.types.stringType,
            "Uuid.parseOrNull parameter must be of type String (sema.types.stringType)"
        )

        let uuidFQ = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        let uuidSym = try #require(sema.symbols.lookup(fqName: uuidFQ))
        guard case .classType(let ct) = sema.types.kind(of: sig.returnType) else {
            Issue.record("Uuid.parseOrNull return type must be a nullable Uuid class type")
            return
        }
        #expect(ct.classSymbol == uuidSym)
        #expect(ct.nullability == .nullable)
    }

    @Test
    func testUuidParseHexAcceptsStringParameter() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "parseHex"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        #expect(!syms.isEmpty, "Uuid.parseHex must be registered")
        let parseHexSym = try #require(syms.first)
        guard let sig = sema.symbols.functionSignature(for: parseHexSym) else {
            Issue.record("Uuid.parseHex has no signature"); return
        }
        #expect(sig.parameterTypes.count == 1, "Uuid.parseHex must take exactly 1 parameter")
        #expect(
            sig.parameterTypes[0] == sema.types.stringType,
            "Uuid.parseHex parameter must be of type String (sema.types.stringType)"
        )
    }

    @Test
    func testUuidParseHexOrNullAcceptsStringParameterAndReturnsNullableUuid() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "parseHexOrNull"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        #expect(!syms.isEmpty, "Uuid.parseHexOrNull must be registered")
        let parseHexOrNullSym = try #require(syms.first)
        guard let sig = sema.symbols.functionSignature(for: parseHexOrNullSym) else {
            Issue.record("Uuid.parseHexOrNull has no signature"); return
        }
        #expect(sig.parameterTypes.count == 1, "Uuid.parseHexOrNull must take exactly 1 parameter")
        #expect(
            sig.parameterTypes[0] == sema.types.stringType,
            "Uuid.parseHexOrNull parameter must be of type String (sema.types.stringType)"
        )

        let uuidFQ = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        let uuidSym = try #require(sema.symbols.lookup(fqName: uuidFQ))
        guard case .classType(let ct) = sema.types.kind(of: sig.returnType) else {
            Issue.record("Uuid.parseHexOrNull return type must be a nullable Uuid class type")
            return
        }
        #expect(ct.classSymbol == uuidSym)
        #expect(ct.nullability == .nullable)
    }

    @Test
    func testUuidParseHexDashAcceptsStringParameter() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "parseHexDash"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        #expect(!syms.isEmpty, "Uuid.parseHexDash must be registered")
        let parseHexDashSym = try #require(syms.first)
        guard let sig = sema.symbols.functionSignature(for: parseHexDashSym) else {
            Issue.record("Uuid.parseHexDash has no signature"); return
        }
        #expect(sig.parameterTypes.count == 1, "Uuid.parseHexDash must take exactly 1 parameter")
        #expect(
            sig.parameterTypes[0] == sema.types.stringType,
            "Uuid.parseHexDash parameter must be of type String (sema.types.stringType)"
        )
    }

    @Test
    func testUuidParseHexDashOrNullAcceptsStringParameterAndReturnsNullableUuid() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "parseHexDashOrNull"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        #expect(!syms.isEmpty, "Uuid.parseHexDashOrNull must be registered")
        let parseHexDashOrNullSym = try #require(syms.first)
        guard let sig = sema.symbols.functionSignature(for: parseHexDashOrNullSym) else {
            Issue.record("Uuid.parseHexDashOrNull has no signature"); return
        }
        #expect(sig.parameterTypes.count == 1, "Uuid.parseHexDashOrNull must take exactly 1 parameter")
        #expect(
            sig.parameterTypes[0] == sema.types.stringType,
            "Uuid.parseHexDashOrNull parameter must be of type String (sema.types.stringType)"
        )

        let uuidFQ = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        let uuidSym = try #require(sema.symbols.lookup(fqName: uuidFQ))
        guard case .classType(let ct) = sema.types.kind(of: sig.returnType) else {
            Issue.record("Uuid.parseHexDashOrNull return type must be a nullable Uuid class type")
            return
        }
        #expect(ct.classSymbol == uuidSym)
        #expect(ct.nullability == .nullable)
    }

    @Test
    func testUuidNameUUIDFromBytesCompanionMethodIsSourceBacked() throws {
        let (ctx, sema, interner) = try makeSemaWithContext()
        #expect(
            isSourceBacked(
                fqPath: ["kotlin", "uuid", "Uuid", "Companion", "nameUUIDFromBytes"],
                ctx: ctx,
                sema: sema,
                interner: interner
            ),
            "Uuid.nameUUIDFromBytes must be declared in Uuid.kt"
        )
    }

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
            "Uuid.fromLongs must be declared in Uuid.kt"
        )
    }

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
            "Uuid.fromByteArray must be declared in Uuid.kt"
        )
    }

    // MARK: - 3. Overload presence: parse vs parseHex

    @Test
    func testUuidParseFactoriesAreDistinctOverloads() throws {
        let (sema, interner) = try makeSema()
        let parseFQ = ["kotlin", "uuid", "Uuid", "Companion", "parse"].map { interner.intern($0) }
        let parseHexFQ = ["kotlin", "uuid", "Uuid", "Companion", "parseHex"].map { interner.intern($0) }
        let parseHexDashFQ = ["kotlin", "uuid", "Uuid", "Companion", "parseHexDash"].map { interner.intern($0) }
        let parseSyms = Set(sema.symbols.lookupAll(fqName: parseFQ))
        let parseHexSyms = Set(sema.symbols.lookupAll(fqName: parseHexFQ))
        let parseHexDashSyms = Set(sema.symbols.lookupAll(fqName: parseHexDashFQ))
        #expect(!parseSyms.isEmpty, "Uuid.parse must be registered")
        #expect(!parseHexSyms.isEmpty, "Uuid.parseHex must be registered")
        #expect(!parseHexDashSyms.isEmpty, "Uuid.parseHexDash must be registered")
        #expect(
            parseSyms.isDisjoint(with: parseHexSyms),
            "parse and parseHex must not share the same SymbolID"
        )
        #expect(
            parseSyms.isDisjoint(with: parseHexDashSyms),
            "parse and parseHexDash must not share the same SymbolID"
        )
        #expect(
            parseHexSyms.isDisjoint(with: parseHexDashSyms),
            "parseHex and parseHexDash must not share the same SymbolID"
        )
    }

    // MARK: - 4. Instance methods: toString / toHexString

    @Test
    func testUuidToStringInstanceMethodIsSourceBacked() throws {
        let (ctx, sema, interner) = try makeSemaWithContext()
        #expect(
            isSourceBacked(
                fqPath: ["kotlin", "uuid", "Uuid", "toString"],
                ctx: ctx,
                sema: sema,
                interner: interner
            ),
            "Uuid.toString() must be declared in Uuid.kt"
        )
    }

    @Test
    func testUuidToHexStringInstanceMethodIsSourceBacked() throws {
        let (ctx, sema, interner) = try makeSemaWithContext()
        #expect(
            isSourceBacked(
                fqPath: ["kotlin", "uuid", "Uuid", "toHexString"],
                ctx: ctx,
                sema: sema,
                interner: interner
            ),
            "Uuid.toHexString() must be declared in Uuid.kt"
        )
    }

    // MARK: - 5. Instance methods: toByteArray and toLongs

    @Test
    func testUuidToByteArrayInstanceMethodIsSourceBacked() throws {
        let (ctx, sema, interner) = try makeSemaWithContext()
        #expect(
            isSourceBacked(
                fqPath: ["kotlin", "uuid", "Uuid", "toByteArray"],
                ctx: ctx,
                sema: sema,
                interner: interner
            ),
            "Uuid.toByteArray() must be declared in Uuid.kt"
        )
    }

    @Test
    func testUuidToByteArrayHasNoParameters() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "toByteArray"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        #expect(!syms.isEmpty, "Uuid.toByteArray must be registered")
        let sym = try #require(syms.first)
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            Issue.record("Uuid.toByteArray has no signature"); return
        }
        #expect(sig.parameterTypes.isEmpty, "Uuid.toByteArray() must take no parameters")
    }

    @Test
    func testUuidToLongsInstanceMethodIsSourceBacked() throws {
        let (ctx, sema, interner) = try makeSemaWithContext()
        #expect(
            isSourceBacked(
                fqPath: ["kotlin", "uuid", "Uuid", "toLongs"],
                ctx: ctx,
                sema: sema,
                interner: interner
            ),
            "Uuid.toLongs() must be declared in Uuid.kt"
        )
    }

    @Test
    func testUuidToLongsHasNoParameters() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "toLongs"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        #expect(!syms.isEmpty, "Uuid.toLongs must be registered")
        let sym = try #require(syms.first)
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            Issue.record("Uuid.toLongs has no signature"); return
        }
        #expect(sig.parameterTypes.isEmpty, "Uuid.toLongs() must take no parameters")
    }

    // MARK: - 6. Instance properties: mostSignificantBits, leastSignificantBits

    @Test
    func testUuidMostSignificantBitsPropertyIsSourceBacked() throws {
        let (ctx, sema, interner) = try makeSemaWithContext()
        #expect(
            isSourceBacked(
                fqPath: ["kotlin", "uuid", "Uuid", "mostSignificantBits"],
                ctx: ctx,
                sema: sema,
                interner: interner
            ),
            "Uuid.mostSignificantBits must be declared in Uuid.kt"
        )
    }

    @Test
    func testUuidLeastSignificantBitsPropertyIsSourceBacked() throws {
        let (ctx, sema, interner) = try makeSemaWithContext()
        #expect(
            isSourceBacked(
                fqPath: ["kotlin", "uuid", "Uuid", "leastSignificantBits"],
                ctx: ctx,
                sema: sema,
                interner: interner
            ),
            "Uuid.leastSignificantBits must be declared in Uuid.kt"
        )
    }

    // MARK: - 7. Instance methods: version and variant

    @Test
    func testUuidVersionInstanceMethodIsSourceBacked() throws {
        let (ctx, sema, interner) = try makeSemaWithContext()
        #expect(
            isSourceBacked(
                fqPath: ["kotlin", "uuid", "Uuid", "version"],
                ctx: ctx,
                sema: sema,
                interner: interner
            ),
            "Uuid.version() must be declared in Uuid.kt"
        )
    }

    @Test
    func testUuidVariantInstanceMethodIsSourceBacked() throws {
        let (ctx, sema, interner) = try makeSemaWithContext()
        #expect(
            isSourceBacked(
                fqPath: ["kotlin", "uuid", "Uuid", "variant"],
                ctx: ctx,
                sema: sema,
                interner: interner
            ),
            "Uuid.variant() must be declared in Uuid.kt"
        )
    }

    // MARK: - 8. NIL constant

    @Test
    func testUuidNILCompanionConstantIsSourceBacked() throws {
        let (ctx, sema, interner) = try makeSemaWithContext()
        #expect(
            isSourceBacked(
                fqPath: ["kotlin", "uuid", "Uuid", "Companion", "NIL"],
                ctx: ctx,
                sema: sema,
                interner: interner
            ),
            "Uuid.NIL must be declared in Uuid.kt"
        )
    }

    @Test
    func testUuidNILReturnTypeIsUuid() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "NIL"].map { interner.intern($0) }
        let nilSym = try #require(
            sema.symbols.lookupAll(fqName: fq).first,
            "Uuid.NIL must be registered"
        )
        let propType = try #require(sema.symbols.propertyType(for: nilSym))
        let uuidFQ = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        let uuidSym = try #require(sema.symbols.lookup(fqName: uuidFQ))

        guard case .classType(let ct) = sema.types.kind(of: propType) else {
            Issue.record("Uuid.NIL property type must be a class type")
            return
        }
        #expect(ct.classSymbol == uuidSym)
    }

    @Test
    func testUuidSizeConstantsAreRegisteredAsConstInts() throws {
        let (sema, interner) = try makeSema()
        let expectedConstants: [(name: String, value: Int64)] = [
            ("SIZE_BITS", 128),
            ("SIZE_BYTES", 16),
        ]

        for expected in expectedConstants {
            let fq = ["kotlin", "uuid", "Uuid", "Companion", expected.name].map { interner.intern($0) }
            let sym = try #require(
                sema.symbols.lookupAll(fqName: fq).first(where: { sema.symbols.symbol($0)?.kind == .property }),
                "Uuid.\(expected.name) must be registered as a companion property"
            )
            let info = try #require(sema.symbols.symbol(sym))
            #expect(info.flags.contains(.constValue), "Uuid.\(expected.name) must be const")
            #expect(
                sema.symbols.propertyType(for: sym) == sema.types.intType,
                "Uuid.\(expected.name) must have Int type"
            )
            #expect(
                sema.symbols.constValueExprKind(for: sym) == .intLiteral(expected.value),
                "Uuid.\(expected.name) must expose the Kotlin stdlib constant value"
            )
        }
    }

    @Test
    func testUuidLexicalOrderComparatorIsSourceBacked() throws {
        let (ctx, sema, interner) = try makeSemaWithContext()
        #expect(
            isSourceBacked(
                fqPath: ["kotlin", "uuid", "Uuid", "Companion", "LEXICAL_ORDER"],
                ctx: ctx,
                sema: sema,
                interner: interner
            ),
            "Uuid.LEXICAL_ORDER must be declared in Uuid.kt"
        )
    }

    @Test
    func testUuidLexicalOrderComparatorType() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "LEXICAL_ORDER"].map { interner.intern($0) }
        let lexicalOrderSym = try #require(
            sema.symbols.lookupAll(fqName: fq).first(where: { sema.symbols.symbol($0)?.kind == .property }),
            "Uuid.LEXICAL_ORDER must be registered as a companion property"
        )

        let propType = try #require(sema.symbols.propertyType(for: lexicalOrderSym))
        guard case .classType(let comparatorType) = sema.types.kind(of: propType) else {
            Issue.record("Uuid.LEXICAL_ORDER type must be kotlin.Comparator<Uuid>")
            return
        }

        let comparatorSym = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "Comparator"].map { interner.intern($0) })
        )
        let uuidSym = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "uuid", "Uuid"].map { interner.intern($0) })
        )

        #expect(comparatorType.classSymbol == comparatorSym)
        guard let firstArg = comparatorType.args.first,
              case .invariant(let uuidType) = firstArg
        else {
            Issue.record("Uuid.LEXICAL_ORDER Comparator type must carry invariant Uuid argument")
            return
        }
        guard case .classType(let uuidClassType) = sema.types.kind(of: uuidType) else {
            Issue.record("Uuid.LEXICAL_ORDER Comparator argument must be Uuid")
            return
        }
        #expect(uuidClassType.classSymbol == uuidSym)
    }

    @Test
    func testKnownPendingUuidCompanionMembersAreTrackedAsGaps() throws {
        let (sema, interner) = try makeSema()
        let pendingMembers: [String] = []

        #expect(pendingMembers.isEmpty, "No UUID companion pending gaps should remain")

        for memberName in pendingMembers {
            let fq = ["kotlin", "uuid", "Uuid", "Companion", memberName].map { interner.intern($0) }
            let syms = sema.symbols.lookupAll(fqName: fq)
            #expect(
                syms.isEmpty,
                "Uuid.\(memberName) is a tracked pending API and must remain absent until its TODO is implemented; found \(syms.count) symbols"
            )
        }
    }

    // MARK: - 9. @ExperimentalUuidApi opt-in annotation — synthesised (STDLIB-EXPERIMENTAL-ABI-001)

    @Test
    func testExperimentalUuidApiAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "ExperimentalUuidApi"].map { interner.intern($0) }
        let sym = sema.symbols.lookup(fqName: fq)
        #expect(
            sym != nil,
            "kotlin.uuid.ExperimentalUuidApi must be registered (STDLIB-EXPERIMENTAL-ABI-001)"
        )
    }

    @Test
    func testExperimentalUuidApiAnnotationIsRequiresOptIn() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "ExperimentalUuidApi"].map { interner.intern($0) }
        let sym = try #require(sema.symbols.lookup(fqName: fq))
        let annotations = sema.symbols.annotations(for: sym)

        #expect(
            annotations.contains {
                $0.annotationFQName == "kotlin.RequiresOptIn" &&
                    $0.arguments.contains("level=RequiresOptIn.Level.ERROR")
            },
            "ExperimentalUuidApi must carry @RequiresOptIn(ERROR), got \(annotations)"
        )
    }

    @Test
    func testExperimentalUuidApiAnnotationCarriesOfficialTargets() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "ExperimentalUuidApi"].map { interner.intern($0) }
        let sym = try #require(sema.symbols.lookup(fqName: fq))
        let annotations = sema.symbols.annotations(for: sym)

        #expect(
            annotations.contains {
                $0.annotationFQName == "kotlin.annotation.Target" &&
                    $0.arguments == [
                        "AnnotationTarget.CLASS",
                        "AnnotationTarget.ANNOTATION_CLASS",
                        "AnnotationTarget.PROPERTY",
                        "AnnotationTarget.FIELD",
                        "AnnotationTarget.LOCAL_VARIABLE",
                        "AnnotationTarget.VALUE_PARAMETER",
                        "AnnotationTarget.CONSTRUCTOR",
                        "AnnotationTarget.FUNCTION",
                        "AnnotationTarget.PROPERTY_GETTER",
                        "AnnotationTarget.PROPERTY_SETTER",
                        "AnnotationTarget.TYPEALIAS",
                    ]
            },
            "ExperimentalUuidApi must carry the official @Target list, got \(annotations)"
        )
    }

    @Test
    func testUuidApiSymbolsAreTaggedExperimentalUuidApi() throws {
        let (sema, interner) = try makeSema()
        let apiPaths = [
            ["kotlin", "uuid", "Uuid"],
            ["kotlin", "uuid", "Uuid", "Companion", "random"],
            ["kotlin", "uuid", "Uuid", "Companion", "NIL"],
            ["kotlin", "uuid", "Uuid", "Companion", "SIZE_BITS"],
            ["kotlin", "uuid", "Uuid", "Companion", "SIZE_BYTES"],
            ["kotlin", "uuid", "Uuid", "Companion", "LEXICAL_ORDER"],
            ["kotlin", "uuid", "Uuid", "Companion", "parse"],
            ["kotlin", "uuid", "Uuid", "Companion", "parseOrNull"],
            ["kotlin", "uuid", "Uuid", "Companion", "parseHex"],
            ["kotlin", "uuid", "Uuid", "Companion", "parseHexOrNull"],
            ["kotlin", "uuid", "Uuid", "Companion", "parseHexDash"],
            ["kotlin", "uuid", "Uuid", "Companion", "parseHexDashOrNull"],
            ["kotlin", "uuid", "Uuid", "Companion", "nameUUIDFromBytes"],
            ["kotlin", "uuid", "Uuid", "Companion", "fromLongs"],
            ["kotlin", "uuid", "Uuid", "Companion", "fromByteArray"],
            ["kotlin", "uuid", "Uuid", "toString"],
            ["kotlin", "uuid", "Uuid", "toHexString"],
            ["kotlin", "uuid", "Uuid", "toLongs"],
            ["kotlin", "uuid", "Uuid", "toByteArray"],
            ["kotlin", "uuid", "Uuid", "version"],
            ["kotlin", "uuid", "Uuid", "variant"],
            ["kotlin", "uuid", "Uuid", "mostSignificantBits"],
            ["kotlin", "uuid", "Uuid", "leastSignificantBits"],
            ["kotlin", "uuid", "toKotlinUuid"],
        ]

        for path in apiPaths {
            let syms = symbols(fqPath: path, sema: sema, interner: interner)
            #expect(!syms.isEmpty, "\(path.joined(separator: ".")) must be registered")
            #expect(
                syms.contains { hasExperimentalUuidApiAnnotation($0, sema: sema) },
                "\(path.joined(separator: ".")) must carry @ExperimentalUuidApi"
            )
        }
    }

    @Test
    func testUuidUsageWithoutOptInEmitsDiagnostic() {
        let source = """
        import kotlin.uuid.Uuid

        fun uuidText(): String = Uuid.NIL.toString()
        """

        let ctx = runUuidSemaCollectingDiagnostics(source)
        let diagnostics = optInDiagnostics(in: ctx)

        #expect(
            !diagnostics.isEmpty,
            "Expected opt-in diagnostics for Uuid usage without @OptIn, got \(ctx.diagnostics.diagnostics)"
        )
        #expect(diagnostics.allSatisfy(isError), "Uuid opt-in diagnostics should be errors")
    }

    @Test
    func testUuidUsageWithOptInSuppressesDiagnostic() {
        let source = """
        import kotlin.OptIn
        import kotlin.uuid.ExperimentalUuidApi
        import kotlin.uuid.Uuid

        @OptIn(ExperimentalUuidApi::class)
        fun uuidText(): String = Uuid.NIL.toString()
        """

        let ctx = runUuidSemaCollectingDiagnostics(source)
        let diagnostics = optInDiagnostics(in: ctx)

        #expect(
            diagnostics.isEmpty,
            "Expected @OptIn(ExperimentalUuidApi::class) to suppress Uuid opt-in diagnostics, got \(ctx.diagnostics.diagnostics)"
        )
    }

    // MARK: - 10. Full API surface inventory

    @Test
    func testAllUuidCompanionMembersAreSourceBacked() throws {
        let (ctx, sema, interner) = try makeSemaWithContext()
        let companionFQ = ["kotlin", "uuid", "Uuid", "Companion"]
        for memberName in [
            "random", "NIL", "LEXICAL_ORDER", "parse", "parseOrNull", "parseHex", "parseHexOrNull",
            "parseHexDash", "parseHexDashOrNull", "nameUUIDFromBytes", "fromLongs", "fromByteArray",
        ] {
            #expect(
                isSourceBacked(fqPath: companionFQ + [memberName], ctx: ctx, sema: sema, interner: interner),
                "Uuid.\(memberName) must be declared in Uuid.kt"
            )
        }
    }

    @Test
    func testAllUuidInstanceMethodsAreSourceBacked() throws {
        let (ctx, sema, interner) = try makeSemaWithContext()
        let classFQ = ["kotlin", "uuid", "Uuid"]
        for member in ["toString", "toHexString", "toLongs", "toByteArray", "version", "variant"] {
            #expect(
                isSourceBacked(fqPath: classFQ + [member], ctx: ctx, sema: sema, interner: interner),
                "Uuid.\(member) must be declared in Uuid.kt"
            )
        }
    }

    @Test
    func testAllUuidPropertiesAreSourceBacked() throws {
        let (ctx, sema, interner) = try makeSemaWithContext()
        let classFQ = ["kotlin", "uuid", "Uuid"]
        for prop in ["mostSignificantBits", "leastSignificantBits"] {
            #expect(
                isSourceBacked(fqPath: classFQ + [prop], ctx: ctx, sema: sema, interner: interner),
                "Uuid.\(prop) must be declared in Uuid.kt"
            )
        }
    }

    // MARK: - 11. toKotlinUuid extension (STDLIB-UUID-FN-004)

    @Test
    func testToKotlinUuidExtensionIsSourceBacked() throws {
        let (ctx, sema, interner) = try makeSemaWithContext()
        #expect(
            isSourceBacked(
                fqPath: ["kotlin", "uuid", "toKotlinUuid"],
                ctx: ctx,
                sema: sema,
                interner: interner
            ),
            "kotlin.uuid.toKotlinUuid must be declared in Uuid.kt"
        )
    }

    @Test
    func testToKotlinUuidReceiverIsJavaUuid() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "toKotlinUuid"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        #expect(!syms.isEmpty, "kotlin.uuid.toKotlinUuid must be registered")
        let sym = try #require(syms.first)
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            Issue.record("toKotlinUuid has no function signature"); return
        }
        let javaUuidFQ = ["java", "util", "UUID"].map { interner.intern($0) }
        guard let javaUuidSym = sema.symbols.lookup(fqName: javaUuidFQ) else {
            Issue.record("java.util.UUID not found in symbol table"); return
        }
        let receiverType = try #require(sig.receiverType, "toKotlinUuid must have a receiver type")
        guard case .classType(let ct) = sema.types.kind(of: receiverType) else {
            Issue.record("toKotlinUuid receiver type is not a class type"); return
        }
        #expect(ct.classSymbol == javaUuidSym, "toKotlinUuid receiver must be java.util.UUID")
    }

    @Test
    func testToKotlinUuidReturnTypeIsKotlinUuid() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "toKotlinUuid"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        #expect(!syms.isEmpty, "kotlin.uuid.toKotlinUuid must be registered")
        let sym = try #require(syms.first)
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            Issue.record("toKotlinUuid has no function signature"); return
        }
        let uuidFQ = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        guard let uuidSym = sema.symbols.lookup(fqName: uuidFQ) else {
            Issue.record("kotlin.uuid.Uuid not found in symbol table"); return
        }
        guard case .classType(let ct) = sema.types.kind(of: sig.returnType) else {
            Issue.record("toKotlinUuid return type is not a class type"); return
        }
        #expect(ct.classSymbol == uuidSym, "toKotlinUuid return type must be kotlin.uuid.Uuid")
    }

    @Test
    func testToKotlinUuidHasNoValueParameters() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "toKotlinUuid"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        #expect(!syms.isEmpty, "kotlin.uuid.toKotlinUuid must be registered")
        let sym = try #require(syms.first)
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            Issue.record("toKotlinUuid has no function signature"); return
        }
        #expect(
            sig.parameterTypes.isEmpty,
            "toKotlinUuid must take no value parameters (receiver-only extension)"
        )
    }

    @Test
    func testToKotlinUuidIsTaggedExperimentalUuidApi() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "toKotlinUuid"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        #expect(!syms.isEmpty, "kotlin.uuid.toKotlinUuid must be registered")
        #expect(
            syms.contains { hasExperimentalUuidApiAnnotation($0, sema: sema) },
            "kotlin.uuid.toKotlinUuid must carry @ExperimentalUuidApi"
        )
    }
}
