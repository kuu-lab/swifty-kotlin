#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
@testable import GoldenHarnessSupport
import Foundation
import Testing
import TestStdlibCache

/// RF-GOLDEN-007 — opt-in `GoldenSemaRenderingContract.fixtureOwned` rendering
/// path. Ordinary `symbol` rows are limited to declarations the RF-GOLDEN-002
/// origin classifier proves fixture-owned (with `.unknown` still surfaced),
/// while `call=`/`ref=`/`type=`/`sig=`/`targs=` spell the RF-GOLDEN-006 public
/// reference. The split happens at render time from ownership and the spec's
/// target list — never by string post-processing — so the default `.current`
/// output stays byte-identical until RF-GOLDEN-008 flips it.
@Suite("GoldenHarness.FixtureOwned")
struct GoldenHarnessFixtureOwnedRenderingTests {
    private func makeTempSource(_ contents: String) throws -> (dir: URL, source: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = dir.appendingPathComponent("case.kt")
        try contents.write(to: source, atomically: false, encoding: .utf8)
        return (dir, source)
    }

    private func renderSema(
        _ source: String,
        injected: [(path: String, contents: String)] = [],
        stdlibLibraryPath: String? = nil,
        spec: GoldenHarnessCaseSpec? = nil,
        contract: GoldenSemaRenderingContract = .fixtureOwned
    ) throws -> String {
        let (dir, sourceURL) = try makeTempSource(source)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try GoldenHarnessDump.dumpSema(
            sourcePath: sourceURL.path,
            preInjectedFiles: injected.map { ($0.path, Data($0.contents.utf8)) },
            stdlibLibraryPath: stdlibLibraryPath,
            caseSpec: spec,
            renderingContract: contract
        )
    }

    private func normalized(_ dump: String) -> String {
        GoldenHarness.normalizedForComparison(suiteName: "Sema", output: dump)
    }

    /// Everything before `section stdlib-targets`: symbol rows, file/decl
    /// lines, expr lines and diagnostics — the part RF-GOLDEN-007 rescopes.
    private func ordinaryPart(of dump: String) -> String {
        dump.components(separatedBy: "section stdlib-targets").first ?? dump
    }

    private func symbolLines(in dump: String) -> [String] {
        dump.split(separator: "\n")
            .filter { $0.hasPrefix("symbol ") }
            .map(String.init)
    }

    private func targetLines(in dump: String) -> [String] {
        dump.split(separator: "\n")
            .drop(while: { $0 != "section stdlib-targets" })
            .dropFirst()
            .filter { $0.hasPrefix("target ") }
            .map(String.init)
    }

    @Test
    func nonLocalReturnMaskOnlyDescribesInlineFunctions() throws {
        let dump = try renderSema("""
        package sample

        fun plain(block: () -> Unit) { block() }
        inline fun restricted(crossinline block: () -> Unit) { block() }
        fun main() {
            plain {}
            restricted {}
        }
        """)
        let calls = dump.split(separator: "\n").filter { $0.hasPrefix("expr ") && $0.contains("call=sample.") }
        let plain = try #require(calls.first { $0.contains("call=sample.plain[") })
        let restricted = try #require(calls.first { $0.contains("call=sample.restricted[") })
        #expect(!plain.contains("nonlocal="))
        #expect(restricted.contains("nonlocal=[0]"))
    }

    /// Fixture exercising data-class synthetics, enum members, accessors,
    /// object literals, a generic bound, a stdlib call with `targs=` and an
    /// `is` check — everything the contract must preserve in one dump.
    private let richFixture = """
    package sample

    data class Name(val value: String)

    enum class E { A, B }

    class Wrapper {
        var backing: Int = 0
        var computed: Int
            get() = backing + 1
            set(v) { backing = v }
    }

    fun <T: Comparable<T>> clamped(x: T): T = x

    class Marker(val id: Int)

    fun main() {
        val n = Name("a")
        n.copy("b")
        n.hashCode()
        val w = Wrapper()
        w.computed = 3
        val obj = object { val x = 1 }
        val listed = listOf(Marker(7))
        clamped(2)
        val eq = E.A == E.B
        val isStr = "s" is String
    }
    """

    // MARK: - Information preservation

    @Test
    func symbolRowsKeepOnlyFixtureOwnedDeclarations() throws {
        let dump = try renderSema(richFixture)
        let rows = symbolLines(in: dump)

        #expect(!rows.isEmpty)
        // Every surviving row is fixture-owned; external declarations never
        // get flags / sig / type rows.
        #expect(rows.allSatisfy { $0.contains(";origin=fixture]") })
        #expect(!rows.contains { $0.contains("fq=kotlin.") || $0.contains("fq=kotlinx.") })

        // Synthetic fixture members stay: object-literal class, data-class
        // `copy`, value/type parameters, locals and destructuring slots.
        #expect(rows.contains { $0.contains("fq=__ObjectLiteral_") && $0.contains("flags=synthetic") })
        #expect(rows.contains { $0.contains("fq=sample.Name.copy[") && $0.contains("flags=synthetic") })
        #expect(rows.contains { $0.contains("[kind=vparam;origin=fixture]") })
        #expect(rows.contains { $0.contains("[kind=tparam;origin=fixture]") })
        #expect(rows.contains { $0.contains("fq=__local_") })
        #expect(rows.contains { $0.contains("fq=sample.Wrapper.computed[kind=prop") })
        #expect(rows.contains { $0.contains("fq=sample.E.A[kind=field") })

        // `hashCode` is a fixture-owned synthetic with no `declSite`: the old
        // declSite proxy dropped its row; the origin classifier keeps it.
        let current = try renderSema(richFixture, contract: .current)
        #expect(rows.contains { $0.contains("fq=sample.Name.hashCode[") })
        #expect(!symbolLines(in: current).contains { $0.contains("fq=sample.Name.hashCode[") })
    }

    @Test
    func referencesUsePublicSpellingAndKeepCollection() throws {
        let dump = try renderSema(richFixture)

        // `call=`/`ref=` use the RF-GOLDEN-006 public projection: fixture
        // symbols carry `;origin=fixture`, library callees the bare public
        // key without it.
        #expect(dump.contains(
            "call=sample.Name.<init>[kind=ctor;recv=sample.Name;params=String;ret=sample.Name;names=[value];origin=fixture]"
        ))
        #expect(dump.contains("call=kotlin.collections.listOf[kind=fun;params=T0;ret=kotlin.collections.List<T0>;gen=1;names=[element]]"))
        // Actual substituted `targs=` survive, including fixture types nested
        // inside external references.
        #expect(dump.contains("targs=[sample.Marker]"))
        #expect(dump.contains("targs=[Int]"))
        #expect(dump.contains("type=kotlin.collections.List<out sample.Marker>"))
        // The fixture enum object appearing as a type argument of a library
        // callee keeps its own `symbol` row.
        #expect(dump.contains("call=kotlin.Enum.equals["))
        #expect(dump.contains("targs=[sample.E]"))
        #expect(symbolLines(in: dump).contains { $0.contains("fq=sample.E[kind=enum") })
    }

    /// `E.A == E.B` must keep spelling the resolved `kotlin.Enum.equals`
    /// callee; a fixture `equals` member must show the fixture target. The
    /// resolution target is information the contract must not erase.
    @Test
    func resolvedCalleeStaysVisibleAcrossOrigins() throws {
        let enumDump = try renderSema("""
        package sample

        enum class E { A, B }

        fun compare(): Boolean = E.A == E.B
        """)
        #expect(enumDump.contains("call=kotlin.Enum.equals[kind=fun;recv=kotlin.Enum<T0>;params=Any?;ret=Boolean"))

        let fixtureDump = try renderSema("""
        package sample

        class C {
            fun equals(other: Any?): Boolean = false
        }

        fun compare(a: C, b: C): Boolean = a.equals(b)
        """)
        #expect(fixtureDump.contains("call=sample.C.equals[kind=fun;recv=sample.C;params=Any?;ret=Boolean;names=[other];origin=fixture]"))
    }

    // MARK: - Origin-driven row filtering

    @Test
    func rowFilterFollowsClassifierNotDeclSite() throws {
        let (sema, symbols, types, interner) = makeSemaModule()
        let sourceManager = SourceManager()
        let bundledFile = sourceManager.addFile(
            path: "bundled/Api.kt",
            contents: Data("package lib\n".utf8),
            origin: .bundledStdlib
        )
        let userFile = sourceManager.addFile(
            path: "input.kt",
            contents: Data("package sample\n".utf8),
            origin: .user
        )
        let packageName = interner.intern("sample")
        let package = symbols.define(
            kind: .package,
            name: packageName,
            fqName: [packageName],
            declSite: nil,
            visibility: .public
        )
        let fnName = interner.intern("f")
        let fixtureFQ = [packageName, fnName]

        let declared = symbols.define(
            kind: .function, name: fnName, fqName: fixtureFQ,
            declSite: SourceRange(
                start: SourceLocation(file: userFile, offset: 0),
                end: SourceLocation(file: userFile, offset: 1)
            ),
            visibility: .public
        )
        symbols.setSourceFileID(userFile, for: declared)
        symbols.setParentSymbol(package, for: declared)

        // Synthetic fixture member: registered to the fixture file but with
        // `declSite == nil` — the `.current` proxy drops it.
        let synthetic = symbols.define(
            kind: .function, name: fnName, fqName: fixtureFQ + [interner.intern("synth")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setSourceFileID(userFile, for: synthetic)

        let bundled = symbols.define(
            kind: .function, name: fnName, fqName: fixtureFQ + [interner.intern("bundled")],
            declSite: SourceRange(
                start: SourceLocation(file: bundledFile, offset: 0),
                end: SourceLocation(file: bundledFile, offset: 1)
            ),
            visibility: .public
        )
        symbols.setSourceFileID(bundledFile, for: bundled)

        let imported = symbols.define(
            kind: .function, name: fnName, fqName: fixtureFQ + [interner.intern("imported")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .importedLibrary]
        )

        let unknown = symbols.define(
            kind: .function, name: interner.intern("mystery"),
            fqName: [interner.intern("unknown"), interner.intern("mystery")],
            declSite: nil,
            visibility: .public
        )

        let ast = ASTModule(declarationCount: 0, tokenCount: 0)
        let ownedCtx = StableRenderContext(
            sema: sema, interner: interner, ast: ast,
            sourceManager: sourceManager, contract: .fixtureOwned
        )
        let currentCtx = StableRenderContext(
            sema: sema, interner: interner, ast: ast,
            sourceManager: sourceManager, contract: .current
        )

        func symbol(_ id: SymbolID) throws -> SemanticSymbol {
            try #require(sema.symbols.symbol(id))
        }

        for (id, owned, current, label) in [
            (declared, true, true, "fixture-declared"),
            (synthetic, true, false, "fixture-synthetic-nil-declSite"),
            (bundled, false, false, "bundled-source"),
            (imported, false, false, "imported-library"),
            (unknown, true, false, "unknown-origin-surfaced"),
        ] as [(SymbolID, Bool, Bool, String)] {
            let symbol = try symbol(id)
            #expect(
                ownedCtx.rendersOrdinarySymbolRow(symbol, sourceFileID: userFile) == owned,
                Comment(rawValue: "\(label) under .fixtureOwned")
            )
            #expect(
                currentCtx.rendersOrdinarySymbolRow(symbol, sourceFileID: userFile) == current,
                Comment(rawValue: "\(label) under .current")
            )
        }
    }

    // MARK: - Non-mutation

    /// Rendering under either contract must not mutate the shared Sema state —
    /// the dump is a projection, never a source of new symbols, flags or
    /// bindings.
    @Test
    func renderingLeavesSemaStateUnmodified() throws {
        let ctx = makeContextFromSource("""
        package sample

        data class Name(val value: String)

        fun main() {
            val n = Name("a")
            n.copy("b")
            val listed = listOf(n)
        }
        """)
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let sourceFileID = try #require(ctx.sourceManager.fileIDs().first {
            ctx.sourceManager.origin(of: $0) == .user
        })

        func snapshot() -> [String] {
            var lines: [String] = []
            for symbol in sema.symbols.allSymbols().sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
                let declSite = symbol.declSite.map {
                    "\($0.start.file.rawValue):\($0.start.offset)-\($0.end.file.rawValue):\($0.end.offset)"
                } ?? "_"
                lines.append([
                    String(symbol.id.rawValue),
                    "\(symbol.kind)",
                    ctx.interner.resolve(symbol.name),
                    symbol.fqName.map { ctx.interner.resolve($0) }.joined(separator: "."),
                    declSite,
                    "\(symbol.visibility)",
                    String(symbol.flags.rawValue),
                    String(sema.symbols.parentSymbol(for: symbol.id)?.rawValue ?? -1),
                    String(sema.symbols.sourceFileID(for: symbol.id)?.rawValue ?? -1),
                    sema.symbols.externalLinkName(for: symbol.id) ?? "_",
                    sema.symbols.functionSignature(for: symbol.id) != nil ? "sig" : "_",
                    sema.symbols.propertyType(for: symbol.id) != nil ? "prop" : "_",
                ].joined(separator: "|"))
            }
            let bindings = sema.bindings
            lines.append("exprTypes=\(bindings.exprTypes.count)")
            lines.append("identifierSymbols=\(bindings.identifierSymbols.count)")
            lines.append("callBindings=\(bindings.callBindings.count)")
            lines.append("declSymbols=\(bindings.declSymbols.count)")
            lines.append("isCheckTargetTypes=\(bindings.isCheckTargetTypes.count)")
            lines.append("castTargetTypes=\(bindings.castTargetTypes.count)")
            for (exprID, binding) in bindings.callBindings.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                lines.append(
                    "call \(exprID.rawValue)=\(binding.chosenCallee.rawValue):" +
                    "\(binding.substitutedTypeArguments.map { String($0.rawValue) }.joined(separator: ",")):" +
                    "\(binding.parameterMapping.sorted { $0.key < $1.key }.map { "\($0.key)->\($0.value)" }.joined(separator: ","))"
                )
            }
            for (exprID, symbolID) in bindings.identifierSymbols.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                lines.append("ref \(exprID.rawValue)=\(symbolID.rawValue)")
            }
            for (exprID, typeID) in bindings.exprTypes.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                lines.append("type \(exprID.rawValue)=\(typeID.rawValue)")
            }
            return lines
        }

        let before = snapshot()
        let currentOut = try GoldenHarnessDump.renderSemaOutput(
            ast: ast, sema: sema, interner: ctx.interner,
            sourceManager: ctx.sourceManager, sourceFileID: sourceFileID,
            diagnostics: ctx.diagnostics, caseSpec: nil,
            renderingContract: .current
        )
        let ownedOut = try GoldenHarnessDump.renderSemaOutput(
            ast: ast, sema: sema, interner: ctx.interner,
            sourceManager: ctx.sourceManager, sourceFileID: sourceFileID,
            diagnostics: ctx.diagnostics, caseSpec: nil,
            renderingContract: .fixtureOwned
        )

        // Sanity: both contracts actually rendered, and differently.
        #expect(currentOut.contains("symbol fq=sample.Name[kind=class]"))
        #expect(ownedOut.contains("symbol fq=sample.Name[kind=class;origin=fixture]"))
        #expect(currentOut != ownedOut)

        #expect(snapshot() == before)
    }

    // MARK: - Invariance (ordinary part)

    /// Bundled decls the fixture never references — moved declSites, extra
    /// symbols, shifted symbol IDs — must not move the ordinary part under
    /// either contract.
    @Test
    func unreferencedBundledChangeLeavesOrdinaryPartUnchanged() throws {
        let source = """
        package sample

        fun f(list: List<Int>): Int = list.size
        """
        let injection = [(
            path: "__bundled_marker.kt",
            contents: "package kotlin.collections\npublic fun <T> List<T>.unusedMarker(): Int = 0\n"
        )]
        for contract in [GoldenSemaRenderingContract.fixtureOwned, .current] {
            let baseline = try renderSema(source, contract: contract)
            let shifted = try renderSema(source, injected: injection, contract: contract)
            #expect(normalized(ordinaryPart(of: baseline)) == normalized(ordinaryPart(of: shifted)))
            // The injected decl is unreferenced: it must not be enumerated.
            #expect(!shifted.contains("unusedMarker"))
        }
    }

    /// Moving the stdlib between source compilation and the imported artifact
    /// changes symbol origins (`stdlibStub` → `importedLibrary`) — that drift
    /// must land only in the dedicated section, never in the ordinary part.
    @Test
    func stdlibOriginChangeOnlyMovesDedicatedSection() throws {
        TestStdlibCache.shared.prepare()
        guard let artifactPath = CompilerOptions.defaultStdlibLibraryPath else {
            Issue.record("stdlib artifact unavailable — skipping artifact-profile comparison")
            return
        }
        let source = """
        package sample

        fun constructAny(): Any = Any()
        fun useList(list: List<Int>): Int = list.size
        """
        let targets = ["kotlin.Any[kind=class]"]
        let sourceDump = try renderSema(
            source,
            spec: GoldenHarnessCaseSpec(stdlibProfile: .source, targets: targets)
        )
        let artifactDump = try renderSema(
            source,
            stdlibLibraryPath: artifactPath,
            spec: GoldenHarnessCaseSpec(stdlibProfile: .artifact, targets: targets)
        )

        #expect(normalized(ordinaryPart(of: sourceDump)) == normalized(ordinaryPart(of: artifactDump)))
        let sourceTargets = targetLines(in: sourceDump)
        let artifactTargets = targetLines(in: artifactDump)
        #expect(sourceTargets.count == 1 && artifactTargets.count == 1)
        #expect(sourceTargets[0].contains("origin=stdlibStub"))
        #expect(artifactTargets[0].contains("origin=importedLibrary"))
    }

    /// A metadata change on the targeted declaration — injecting a real
    /// bundled `class Any` over the synthetic stub — diffs only the section
    /// that owns it.
    @Test
    func targetMetadataDriftStaysInDedicatedSection() throws {
        let source = """
        package sample

        fun f(): Int = 1
        """
        let spec = GoldenHarnessCaseSpec(
            stdlibProfile: .source,
            targets: ["kotlin.Any[kind=class]"]
        )
        let baseline = try renderSema(source, spec: spec)
        let injected = try renderSema(
            source,
            injected: [(
                path: "__bundled_any.kt",
                contents: """
                package kotlin
                public class Any {
                    public constructor()
                    public open fun toString(): String = "Any"
                    public open fun equals(other: Any?): Boolean = this === other
                    public open fun hashCode(): Int = 0
                }

                """
            )],
            spec: spec
        )
        #expect(normalized(ordinaryPart(of: baseline)) == normalized(ordinaryPart(of: injected)))
        #expect(targetLines(in: baseline).contains { $0.contains("origin=stdlibStub") })
        #expect(targetLines(in: injected).contains { $0.contains("origin=bundledSource") })
    }

    /// Changing `List`'s surface must not move a case that merely mentions
    /// `List` as a type — only cases that target `List` may diff.
    @Test
    func unrelatedTargetCaseUnaffectedByListMetadataChange() throws {
        let source = """
        package sample

        fun useList(list: List<Int>): Int = list.size
        """
        let spec = GoldenHarnessCaseSpec(
            stdlibProfile: .source,
            targets: ["kotlin.Any[kind=class]"]
        )
        let baseline = try renderSema(source, spec: spec)
        let shifted = try renderSema(
            source,
            injected: [(
                path: "__bundled_marker.kt",
                contents: "package kotlin.collections\npublic fun <T> List<T>.injectedExt(): Int = 0\n"
            )],
            spec: spec
        )
        #expect(normalized(baseline) == normalized(shifted))
        #expect(targetLines(in: shifted).contains { $0.contains("fq=kotlin.Any[kind=class]") })
    }

    // MARK: - Sensitivity

    /// Any change in fixture-visible semantics — params, inferred types,
    /// overload choice, bounds, diagnostics — must still diff the ordinary
    /// part under the new contract.
    @Test
    func fixtureDeclarationChangePropagates() throws {
        let intDump = try renderSema("""
        package sample

        fun pick(list: List<Int>): Int = list.size
        """)
        let longDump = try renderSema("""
        package sample

        fun pick(list: List<Long>): Int = list.size
        """)
        #expect(intDump.contains("symbol fq=sample.pick[kind=fun;params=kotlin.collections.List<Int>;"))
        #expect(longDump.contains("symbol fq=sample.pick[kind=fun;params=kotlin.collections.List<Long>;"))
        #expect(normalized(intDump) != normalized(longDump))
    }

    @Test
    func inferredTypeChangePropagates() throws {
        let intDump = try renderSema("""
        package sample

        fun f() {
            val x = 1
        }
        """)
        let stringDump = try renderSema("""
        package sample

        fun f() {
            val x = "s"
        }
        """)
        #expect(intDump.contains("type=Int"))
        #expect(stringDump.contains("type=String"))
        #expect(normalized(intDump) != normalized(stringDump))
    }

    @Test
    func overloadChoiceChangePropagates() throws {
        let intDump = try renderSema("""
        package sample

        fun pick(x: Int): Int = x
        fun pick(x: String): String = x

        fun main() { pick(1) }
        """)
        let stringDump = try renderSema("""
        package sample

        fun pick(x: Int): Int = x
        fun pick(x: String): String = x

        fun main() { pick("s") }
        """)
        #expect(intDump.contains("call=sample.pick[kind=fun;params=Int;"))
        #expect(stringDump.contains("call=sample.pick[kind=fun;params=String;"))
        #expect(normalized(intDump) != normalized(stringDump))
    }

    @Test
    func typeConstraintChangePropagates() throws {
        let boundDump = try renderSema("""
        package sample

        fun <T: Comparable<T>> clamped(x: T): T = x
        """)
        let unboundDump = try renderSema("""
        package sample

        fun <T> clamped(x: T): T = x
        """)
        #expect(boundDump.contains("bounds=[kotlin.Comparable<T0>]"))
        #expect(!unboundDump.contains("bounds=["))
        #expect(normalized(boundDump) != normalized(unboundDump))
    }

    @Test
    func diagnosticChangePropagates() throws {
        let cleanDump = try renderSema("""
        package sample

        fun f(): Int = 1
        """)
        let brokenDump = try renderSema("""
        package sample

        fun f(): Int = "s"
        """)
        #expect(!cleanDump.contains("diagnostic severity=error"))
        #expect(brokenDump.contains("diagnostic severity=error"))
        #expect(normalized(cleanDump) != normalized(brokenDump))
    }

    // MARK: - Dedicated section under the contract

    /// The RF-GOLDEN-011 section renders identically under both contracts —
    /// specs are written in stable-key spelling and stay there.
    @Test
    func targetSectionIsContractIndependent() throws {
        let spec = GoldenHarnessCaseSpec(
            stdlibProfile: .source,
            targets: ["kotlin.Any[kind=class]", "kotlin.Any.<init>[kind=ctor;params=]"]
        )
        let current = try renderSema(
            "package sample\n\nfun constructAny(): Any = Any()\n",
            spec: spec, contract: .current
        )
        let owned = try renderSema(
            "package sample\n\nfun constructAny(): Any = Any()\n",
            spec: spec
        )
        #expect(targetLines(in: current) == targetLines(in: owned))
        #expect(targetLines(in: owned).count == 2)
    }

    /// A spec's missing target must still fail under the new contract —
    /// reducing ordinary rows can never substitute for dedicated coverage.
    @Test
    func unresolvedTargetStillFails() throws {
        #expect(throws: GoldenHarnessTargetError.self) {
            _ = try renderSema(
                "package sample\n\nfun f(): Int = 1\n",
                spec: GoldenHarnessCaseSpec(
                    stdlibProfile: .source,
                    targets: ["kotlin.DoesNotExist[kind=class]"]
                )
            )
        }
    }
}
#endif
