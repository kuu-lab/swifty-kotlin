#if canImport(Testing)
@testable import GoldenHarnessSupport
import Foundation
import Testing

/// RF-GOLDEN-011/012 — dedicated `section stdlib-targets` output and explicit
/// `stdlib-profile` execution modes. Ordinary cases stay untouched; a
/// `.golden-spec` file pins the profile a case verifies and lists the
/// library-owned declarations it claims responsibility for.
@Suite("GoldenHarness.TargetedGolden")
struct GoldenHarnessTargetedGoldenTests {
    private func makeTempSource(
        _ contents: String,
        spec: String? = nil
    ) throws -> (dir: URL, source: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = dir.appendingPathComponent("case.kt")
        try contents.write(to: source, atomically: false, encoding: .utf8)
        if let spec {
            try spec.write(
                to: GoldenHarnessCaseSpec.specURL(forSourceURL: source),
                atomically: false,
                encoding: .utf8
            )
        }
        return (dir, source)
    }

    private func renderSema(
        _ source: String,
        spec: GoldenHarnessCaseSpec?
    ) throws -> String {
        let (dir, sourceURL) = try makeTempSource(source)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try GoldenHarnessDump.dumpSema(sourcePath: sourceURL.path, caseSpec: spec)
    }

    private func targetLines(in dump: String) -> [String] {
        dump.split(separator: "\n")
            .drop(while: { $0 != "section stdlib-targets" })
            .dropFirst()
            .filter { $0.hasPrefix("target ") }
            .map(String.init)
    }

    // MARK: - Spec parsing

    @Test
    func specParsesProfileAndTargets() throws {
        let spec = try GoldenHarnessCaseSpec.parse("""
        # comment
        version=1
        stdlib-profile=artifact
        target=kotlin.Any[kind=class]
        target=kotlin.Any.<init>[kind=ctor;params=]
        """, path: "case.golden-spec")

        #expect(spec.stdlibProfile == .artifact)
        #expect(spec.targets == [
            "kotlin.Any[kind=class]",
            "kotlin.Any.<init>[kind=ctor;params=]",
        ])
    }

    @Test
    func specRejectsMalformedInput() throws {
        // Unknown keys are rejected — a spec that does not parse cleanly must
        // not silently downgrade the case to ordinary output.
        #expect(throws: GoldenHarnessCaseSpecError.self) {
            try GoldenHarnessCaseSpec.parse("version=1\nstdlib-profile=artifact\nbogus=1\n", path: "s")
        }
        // version must be first and supported.
        #expect(throws: GoldenHarnessCaseSpecError.self) {
            try GoldenHarnessCaseSpec.parse("stdlib-profile=artifact\nversion=1\n", path: "s")
        }
        #expect(throws: GoldenHarnessCaseSpecError.self) {
            try GoldenHarnessCaseSpec.parse("version=2\nstdlib-profile=artifact\n", path: "s")
        }
        #expect(throws: GoldenHarnessCaseSpecError.self) {
            try GoldenHarnessCaseSpec.parse("stdlib-profile=artifact\n", path: "s")
        }
        // Duplicate target.
        #expect(throws: GoldenHarnessCaseSpecError.self) {
            try GoldenHarnessCaseSpec.parse(
                "version=1\nstdlib-profile=artifact\ntarget=a.B[kind=class]\ntarget=a.B[kind=class]\n",
                path: "s"
            )
        }
        // Targets without an explicit profile are rejected: the verification
        // mode must never be implicit once targets are declared.
        #expect(throws: GoldenHarnessCaseSpecError.self) {
            try GoldenHarnessCaseSpec.parse("version=1\ntarget=kotlin.Any[kind=class]\n", path: "s")
        }
        // Invalid profile value.
        #expect(throws: GoldenHarnessCaseSpecError.self) {
            try GoldenHarnessCaseSpec.parse("version=1\nstdlib-profile=bogus\n", path: "s")
        }
        // A spec with neither profile nor targets is meaningless.
        #expect(throws: GoldenHarnessCaseSpecError.self) {
            try GoldenHarnessCaseSpec.parse("version=1\n", path: "s")
        }
    }

    @Test
    func profileOnlySpecIsValid() throws {
        let spec = try GoldenHarnessCaseSpec.parse(
            "version=1\nstdlib-profile=source\n",
            path: "s"
        )
        #expect(spec.stdlibProfile == .source)
        #expect(spec.targets.isEmpty)
    }

    // MARK: - Golden file naming

    @Test
    func specAwareGoldenURLSuffixesProfile() throws {
        let (dir, source) = try makeTempSource(
            "package sample\n",
            spec: "version=1\nstdlib-profile=artifact\ntarget=kotlin.Any[kind=class]\n"
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        let caseFile = GoldenHarnessCaseFile(sourceURL: source)
        #expect(caseFile.spec?.stdlibProfile == .artifact)
        #expect(caseFile.goldenURL.lastPathComponent == "case.artifact.golden")
    }

    @Test
    func specFreeCaseKeepsLegacyGoldenName() throws {
        let (dir, source) = try makeTempSource("package sample\n")
        defer { try? FileManager.default.removeItem(at: dir) }

        let caseFile = GoldenHarnessCaseFile(sourceURL: source)
        #expect(caseFile.spec == nil)
        #expect(caseFile.specLoadError == nil)
        #expect(caseFile.goldenURL.lastPathComponent == "case.golden")
    }

    @Test
    func brokenSpecIsReportedNotSilentlyDowngraded() throws {
        let (dir, source) = try makeTempSource(
            "package sample\n",
            spec: "version=1\nstdlib-profile=bogus\n"
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        let caseFile = GoldenHarnessCaseFile(sourceURL: source)
        #expect(caseFile.spec == nil)
        #expect(caseFile.specLoadError != nil)
        // Render must fail loudly rather than emit legacy output for a
        // spec-carrying case.
        #expect(throws: GoldenHarnessAPIError.self) {
            _ = try GoldenHarness.render(suiteName: "Sema", sourcePath: source.path)
        }
        #expect(GoldenHarness.resolvedStdlibProfile(forSourcePath: source.path) == nil)
    }

    // MARK: - Profile resolution

    @Test
    func artifactProfileWithoutPathFailsInsteadOfDowngrading() throws {
        let (dir, source) = try makeTempSource("package sample\nfun f(): Int = 1\n")
        defer { try? FileManager.default.removeItem(at: dir) }

        let spec = GoldenHarnessCaseSpec(stdlibProfile: .artifact, targets: [])
        #expect(throws: GoldenHarnessDumpError.self) {
            _ = try GoldenHarnessDump.dumpSema(
                sourcePath: source.path,
                stdlibLibraryPath: nil,
                caseSpec: spec
            )
        }
    }

    @Test
    func noStdlibProfileOmitsBundledDeclarations() throws {
        // `println` must not resolve without stdlib; the fixture's own decl
        // still dumps. This pins that `no-stdlib` really skips injection.
        let dump = try renderSema(
            "package sample\n\nfun f(): Int = 1\n",
            spec: GoldenHarnessCaseSpec(stdlibProfile: .noStdlib, targets: [])
        )
        #expect(dump.contains("symbol fq=sample.f[kind=fun;params=]"))
        #expect(!dump.contains("section stdlib-targets"))
    }

    // MARK: - Target resolution

    @Test
    func fullKeyTargetResolvesBundledStdlibSymbol() throws {
        let dump = try renderSema(
            "package sample\n\nfun constructAny(): Any = Any()\n",
            spec: GoldenHarnessCaseSpec(
                stdlibProfile: .source,
                targets: ["kotlin.Any[kind=class]", "kotlin.Any.<init>[kind=ctor;params=]"]
            )
        )
        let lines = targetLines(in: dump)
        #expect(lines.count == 2)
        // `kotlin.Any` is registered as a synthetic root stub, not a bundled
        // source declaration — hence `stdlibStub`, which is still an allowed
        // stdlib-owned origin.
        #expect(lines.contains { $0.contains("fq=kotlin.Any[kind=class]") && $0.contains("origin=stdlibStub") && $0.contains("kind=class") })
        #expect(lines.contains { $0.contains("fq=kotlin.Any.<init>[kind=ctor;params=]") && $0.contains("sig=") })
    }

    @Test
    func bareFQNameTargetResolvesUniqueSymbol() throws {
        let dump = try renderSema(
            "package sample\n\nfun constructAny(): Any = Any()\n",
            spec: GoldenHarnessCaseSpec(stdlibProfile: .source, targets: ["kotlin.Any"])
        )
        let lines = targetLines(in: dump)
        #expect(lines.count == 1)
        #expect(lines[0].contains("fq=kotlin.Any[kind=class]"))
    }

    @Test
    func unresolvedTargetFails() throws {
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

    @Test
    func fixtureSymbolTargetIsRejected() throws {
        // A case must not claim responsibility for its own declarations —
        // ordinary `symbol`/`decl` output already covers them.
        #expect(throws: GoldenHarnessTargetError.self) {
            _ = try renderSema(
                "package sample\n\nfun f(): Int = 1\n",
                spec: GoldenHarnessCaseSpec(
                    stdlibProfile: .source,
                    targets: ["sample.f[kind=fun;params=]"]
                )
            )
        }
    }

    // MARK: - Section content

    @Test
    func nominalTargetPinsVarianceAndSupertypes() throws {
        // kotlin.Pair is a bundled-source nominal with two invariant type
        // parameters and a kotlin.Any supertype.
        let dump = try renderSema(
            "package sample\n\nfun makePair(first: Int, second: String): Pair<Int, String> = Pair(first, second)\n",
            spec: GoldenHarnessCaseSpec(
                stdlibProfile: .source,
                targets: ["kotlin.Pair[kind=class;gen=2]"]
            )
        )
        let lines = targetLines(in: dump)
        #expect(lines.count == 1)
        let pair = lines[0]
        #expect(pair.contains("tparams=[T0(out),T1(out)]"))
        #expect(pair.contains("supertypes=["))
        #expect(pair.contains("kotlin.Any"))
    }

    @Test
    func targetSectionDoesNotExpandTransitively() throws {
        // Only the requested symbols appear — bounds/supertype type
        // references must not pull their own metadata rows into the section.
        let dump = try renderSema(
            "package sample\n\nfun constructAny(): Any = Any()\n",
            spec: GoldenHarnessCaseSpec(
                stdlibProfile: .source,
                targets: ["kotlin.Any[kind=class]"]
            )
        )
        let lines = targetLines(in: dump)
        #expect(lines.count == 1)
    }

    @Test
    func targetSectionSurvivesComparisonNormalization() throws {
        // The Sema comparison normalizer must not corrupt `target` lines
        // (file-key / symbol-namespace regexes could otherwise rewrite them).
        let dump = try renderSema(
            "package sample\n\nfun constructAny(): Any = Any()\n",
            spec: GoldenHarnessCaseSpec(
                stdlibProfile: .source,
                targets: ["kotlin.Any[kind=class]"]
            )
        )
        let normalized = GoldenHarness.normalizedForComparison(suiteName: "Sema", output: dump)
        let lines = targetLines(in: normalized)
        #expect(lines.count == 1)
        #expect(lines[0].contains("fq=kotlin.Any[kind=class]"))
        #expect(lines[0].contains("origin=stdlibStub"))
    }

    @Test
    func specFreeCaseOutputIsUnchanged() throws {
        // Nil spec must be a byte-identical no-op for existing cases.
        let (dir, source) = try makeTempSource(
            "package sample\n\nfun f(): Int = 1\n"
        )
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = try GoldenHarnessDump.dumpSema(sourcePath: source.path)
        let withNilSpec = try GoldenHarnessDump.dumpSema(sourcePath: source.path, caseSpec: nil)
        #expect(legacy == withNilSpec)
        #expect(!legacy.contains("section stdlib-targets"))
    }
}
#endif
