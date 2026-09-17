#if canImport(Testing)
@testable import GoldenHarnessSupport
import Foundation
import Testing

/// RF-GOLDEN-013 — full-corpus discovery and dedicated-target ownership.
///
/// The golden execution suites intentionally select batches, but this suite
/// audits the unsharded corpus first. The checked-in dedicated case set is
/// explicit here so deleting both a spec and its profile-suffixed golden, then
/// quietly falling back to a legacy golden, is still a review-visible change.
@Suite("GoldenHarness.Inventory")
struct GoldenHarnessInventoryTests {
    private static let requiredTargetedCases: Set<String> = [
        "Sema/stdlib_kotlin_Any_n_n.kt",
        "Sema/stdlib_kotlin_Pair_n_n.kt",
    ]

    private static let requiredTargetContracts: Set<String> = [
        "artifact|kotlin.Any[kind=class]",
        "artifact|kotlin.Any.<init>[kind=ctor;params=]",
        "artifact|kotlin.Pair[kind=class;gen=2]",
        "artifact|kotlin.Pair.<init>[kind=ctor;recv=kotlin.Pair<T0,T1>;params=T0,T1;gen=2]",
    ]

    @Test
    func committedCorpusHasCompleteDedicatedInventory() throws {
        let inventory = try GoldenHarnessCaseDiscovery.preflightAllSuites()

        #expect(inventory.caseCountBySuite.count == GoldenHarnessGoldenSuite.allCases.count)
        #expect(inventory.caseCount > 0)
        #expect(inventory.caseCountByProfile["implicit"] ?? 0 > 0)
        #expect((inventory.caseCountByProfile["artifact"] ?? 0) == Self.requiredTargetedCases.count)
        #expect(inventory.targetedCaseKeys == Self.requiredTargetedCases)
        #expect(inventory.targetContracts == Self.requiredTargetContracts)

        print(
            "GoldenHarness inventory gate: cases=\(inventory.caseCount) "
                + "by-suite=\(inventory.caseCountBySuite) "
                + "by-profile=\(inventory.caseCountByProfile) "
                + "targeted=\(inventory.targetedCaseKeys.count) "
                + "contracts=\(inventory.targetContracts.count)"
        )
    }

    @Test
    func orphanedGoldenIsRejected() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try "stale\n".write(
            to: root.appendingPathComponent("Sema/orphan.golden"),
            atomically: false,
            encoding: .utf8
        )

        try expectInventoryFailure(containing: "orphaned or stale .golden", root: root)
    }

    @Test
    func orphanedSpecIsRejected() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try "version=1\nstdlib-profile=artifact\n".write(
            to: root.appendingPathComponent("Sema/orphan.golden-spec"),
            atomically: false,
            encoding: .utf8
        )

        try expectInventoryFailure(containing: "orphaned .golden-spec", root: root)
    }

    @Test
    func deletedSpecCannotLeaveProfileGoldenAsLegacyCase() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try addCase(
            root: root,
            suite: .sema,
            name: "deleted_spec",
            goldenSuffix: "artifact",
            golden: "section stdlib-targets\ntarget fq=kotlin.Any[kind=class] origin=importedLibrary kind=class vis=public flags=synthetic\n"
        )

        try expectInventoryFailure(containing: "orphaned or stale .golden", root: root)
    }

    @Test
    func invalidSpecIsRejectedBeforeDiscoveryCanDowngradeIt() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try addCase(
            root: root,
            suite: .sema,
            name: "invalid_schema",
            spec: "version=2\nstdlib-profile=artifact\n",
            golden: ""
        )

        try expectInventoryFailure(containing: "invalid .golden-spec", root: root)
    }

    @Test
    func profileAndGoldenPathMustStayInSync() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try addCase(
            root: root,
            suite: .sema,
            name: "profile_mismatch",
            spec: "version=1\nstdlib-profile=artifact\n",
            goldenSuffix: "source",
            golden: ""
        )

        try expectInventoryFailure(containing: "missing expected golden", root: root)
    }

    @Test
    func duplicateTargetIsDetectedAcrossEntireCorpus() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let spec = "version=1\nstdlib-profile=artifact\ntarget=kotlin.Any[kind=class]\n"
        let golden = "section stdlib-targets\ntarget fq=kotlin.Any[kind=class] origin=importedLibrary kind=class vis=public flags=synthetic\n"
        try addCase(root: root, suite: .sema, name: "first_owner", spec: spec, goldenSuffix: "artifact", golden: golden)
        try addCase(root: root, suite: .sema, name: "second_owner", spec: spec, goldenSuffix: "artifact", golden: golden)

        // These two cases can be placed in different execution shards. The
        // inventory gate must see both before shard selection.
        try expectInventoryFailure(containing: "duplicate stdlib target contract", root: root)
    }

    @Test
    func targetSpecAndExpectedSectionMustStayInSync() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try addCase(
            root: root,
            suite: .sema,
            name: "missing_expected_target",
            spec: "version=1\nstdlib-profile=artifact\ntarget=kotlin.Any[kind=class]\n",
            goldenSuffix: "artifact",
            golden: ""
        )

        try expectInventoryFailure(containing: "declared target 'kotlin.Any[kind=class]' is absent", root: root)
    }

    @Test
    func collidingExpectedGoldenPathsAreRejected() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try addCase(
            root: root,
            suite: .sema,
            name: "foo",
            spec: "version=1\nstdlib-profile=artifact\n",
            goldenSuffix: "artifact",
            golden: ""
        )
        try addCase(root: root, suite: .sema, name: "foo.artifact", golden: "")

        try expectInventoryFailure(containing: "multiple .kt cases map to the same expected golden", root: root)
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        for suite in GoldenHarnessGoldenSuite.allCases {
            let directory = root.appendingPathComponent(suite.rawValue, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try "\n".write(
                to: directory.appendingPathComponent("baseline.kt"),
                atomically: false,
                encoding: .utf8
            )
            try "\n".write(
                to: directory.appendingPathComponent("baseline.golden"),
                atomically: false,
                encoding: .utf8
            )
        }
        return root
    }

    private func addCase(
        root: URL,
        suite: GoldenHarnessGoldenSuite,
        name: String,
        spec: String? = nil,
        goldenSuffix: String = "golden",
        golden: String
    ) throws {
        let directory = root.appendingPathComponent(suite.rawValue, isDirectory: true)
        try "\n".write(
            to: directory.appendingPathComponent("\(name).kt"),
            atomically: false,
            encoding: .utf8
        )
        if let spec {
            try spec.write(
                to: directory.appendingPathComponent("\(name).golden-spec"),
                atomically: false,
                encoding: .utf8
            )
        }
        let goldenName = goldenSuffix == "golden"
            ? "\(name).golden"
            : "\(name).\(goldenSuffix).golden"
        try golden.write(
            to: directory.appendingPathComponent(goldenName),
            atomically: false,
            encoding: .utf8
        )
    }

    private func expectInventoryFailure(containing text: String, root: URL) throws {
        do {
            _ = try GoldenHarnessCaseDiscovery.preflightAllSuites(in: root)
            Issue.record("Expected inventory preflight to fail with '\(text)'")
        } catch {
            #expect(String(describing: error).contains(text))
        }
    }
}
#endif
