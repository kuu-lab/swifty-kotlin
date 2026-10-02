#if canImport(Testing)
@testable import CompilerCore
import Foundation
#if canImport(Dispatch)
import Dispatch
#endif
import Testing

// MARK: - KUU-809: nominal layout synthesis bounds for untrusted supertype graphs
//
// `.kklib` metadata is attacker-controlled input: `superFq=` records become
// `directSupertypes` edges verbatim, and `LayoutSynthesis` used to walk them
// with a recursive DFS that spent one native stack frame per inheritance
// level. These tests pin the replacement: an explicit worklist with an
// inheritance-depth limit and a library-wide nominal-type cap, where cycles
// and over-limit graphs surface as validation errors instead of stack
// exhaustion.
@Suite
struct LayoutSynthesisInheritanceLimitTests {

    // MARK: - Unit-level traversal bounds

    /// A chain longer than the depth limit is refused with a single
    /// SUPER-DEPTH error and no stack growth — the DFS runs on an explicit
    /// worklist, so this is exercised on a thin (512 KiB) caller stack to make
    /// a regression observable as a crash rather than a wrong result.
    @Test
    func testChainBeyondDepthLimitIsRejectedWithoutStackGrowth() throws {
        let fixture = NominalChainFixture(classCount: 64)
        fixture.chainSupertypes()

        let diagnostics = DiagnosticEngine()
        try runOnThinStack {
            DataFlowSemaPhase().synthesizeNominalLayouts(
                symbols: fixture.symbols,
                types: fixture.types,
                interner: fixture.interner,
                diagnostics: diagnostics,
                maxInheritanceDepth: 8,
                maxTypeCount: 1_000
            )
        }

        let depthErrors = diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-SUPER-DEPTH" }
        #expect(depthErrors.count == 1)
        #expect(depthErrors.first?.severity == .error)
        // Refusing the deep edge does not drop the node itself: every class
        // still receives a layout once its own root is processed.
        for symbol in fixture.classSymbols {
            #expect(fixture.symbols.nominalLayout(for: symbol) != nil)
        }
    }

    /// A chain at exactly the depth limit is processed to completion in the
    /// deterministic base-first order (each superclass's layout exists before
    /// its subclass is synthesized, so inherited fields accumulate).
    @Test
    func testChainAtExactlyDepthLimitProcessesDeterministically() throws {
        let depth = 8
        let fixture = NominalChainFixture(classCount: depth)
        fixture.chainSupertypes()
        fixture.addFieldPerClass()

        let diagnostics = DiagnosticEngine()
        DataFlowSemaPhase().synthesizeNominalLayouts(
            symbols: fixture.symbols,
            types: fixture.types,
            interner: fixture.interner,
            diagnostics: diagnostics,
            maxInheritanceDepth: depth,
            maxTypeCount: 1_000
        )

        #expect(diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)
        for (index, symbol) in fixture.classSymbols.enumerated() {
            let layout = try #require(fixture.symbols.nominalLayout(for: symbol))
            if index == fixture.classSymbols.count - 1 {
                #expect(layout.superClass == nil)
            } else {
                #expect(layout.superClass == fixture.classSymbols[index + 1])
                // One own field per level plus the inherited suffix: the leaf
                // only reaches this count if every base was laid out first.
                #expect(layout.instanceFieldCount == fixture.classSymbols.count - index)
            }
        }
    }

    /// A supertype cycle is rejected as a validation error (once per
    /// re-entered node) instead of being silently tolerated.
    @Test
    func testCyclicSupertypesEmitDiagnostic() throws {
        let fixture = NominalChainFixture(classCount: 2)
        let a = fixture.classSymbols[0]
        let b = fixture.classSymbols[1]
        fixture.symbols.setDirectSupertypes([b], for: a)
        fixture.symbols.setDirectSupertypes([a], for: b)

        let diagnostics = DiagnosticEngine()
        DataFlowSemaPhase().synthesizeNominalLayouts(
            symbols: fixture.symbols,
            types: fixture.types,
            interner: fixture.interner,
            diagnostics: diagnostics
        )

        let cycleErrors = diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-SUPER-CYCLE" }
        #expect(cycleErrors.count == 1)
        #expect(cycleErrors.first?.severity == .error)
        #expect(fixture.symbols.nominalLayout(for: a) != nil)
        #expect(fixture.symbols.nominalLayout(for: b) != nil)
    }

    /// A diamond (`D : B, C`; `B, C : A`) must process the shared base once:
    /// the leaf's inherited field count includes `A`'s fields exactly once and
    /// no diagnostic is emitted.
    @Test
    func testDiamondSupertypesProcessSharedBaseOnce() throws {
        let fixture = NominalChainFixture(classCount: 4)
        // Order the leaf first so its DFS meets the shared base twice within
        // a single descent: D : B, C with B : A and C : A.
        let d = fixture.classSymbols[0]
        let b = fixture.classSymbols[1]
        let c = fixture.classSymbols[2]
        let a = fixture.classSymbols[3]
        fixture.symbols.setDirectSupertypes([a], for: b)
        fixture.symbols.setDirectSupertypes([a], for: c)
        fixture.symbols.setDirectSupertypes([b, c], for: d)
        fixture.addFieldPerClass()

        let diagnostics = DiagnosticEngine()
        DataFlowSemaPhase().synthesizeNominalLayouts(
            symbols: fixture.symbols,
            types: fixture.types,
            interner: fixture.interner,
            diagnostics: diagnostics
        )

        #expect(diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)
        for symbol in fixture.classSymbols {
            #expect(fixture.symbols.nominalLayout(for: symbol) != nil)
        }
        let dLayout = try #require(fixture.symbols.nominalLayout(for: d))
        // D's superclass is B (lowest raw ID of the non-interface supers), so
        // its fields are A.f + B.f + D.f. If the diamond re-processed A, the
        // shared base's contribution would be counted twice.
        #expect(dLayout.instanceFieldCount == 3)
    }

    /// The library-wide nominal-type cap stops the traversal once the bound
    /// is hit and reports it once.
    @Test
    func testNominalTypeCountBeyondLimitIsRejected() throws {
        let fixture = NominalChainFixture(classCount: 6)

        let diagnostics = DiagnosticEngine()
        DataFlowSemaPhase().synthesizeNominalLayouts(
            symbols: fixture.symbols,
            types: fixture.types,
            interner: fixture.interner,
            diagnostics: diagnostics,
            maxInheritanceDepth: 16,
            maxTypeCount: 3
        )

        let countErrors = diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-SUPER-COUNT" }
        #expect(countErrors.count == 1)
        #expect(countErrors.first?.severity == .error)
    }

    // MARK: - End-to-end through .kklib metadata

    /// The full attack path: a crafted `.kklib` whose `superFq` records form a
    /// chain deeper than `maxNominalLayoutInheritanceDepth`. Compilation must
    /// reject it with the depth diagnostic rather than exhausting the stack —
    /// 1100 classes comfortably exceed the recursive DFS's headroom on the
    /// thin stacks tests run under.
    @Test
    func testKklibInheritanceChainOverDepthLimitIsRejected() throws {
        let depth = DataFlowSemaPhase.maxNominalLayoutInheritanceDepth + 76
        // Emit the leaf first: SymbolIDs are assigned in record order and the
        // DFS starts from the lowest raw ID, so `N0` (the deepest subclass,
        // whose super chain is the full depth) must be defined first for the
        // descent to exceed the limit.
        var lines = ["symbols=\(depth)"]
        for index in 0 ..< depth {
            let supertype = index == depth - 1 ? "" : " superFq=evil.N\(index + 1)"
            lines.append("class _ fq=evil.N\(index) schema=v1\(supertype)")
        }
        let metadata = lines.joined(separator: "\n") + "\n"

        try withKklibDirectory(moduleName: "EvilDeep", metadata: metadata) { libDirPath in
            try withTemporaryFile(contents: "fun main() = 0") { path in
                let ctx = makeCompilationContext(
                    inputs: [path],
                    moduleName: "EvilDeepApp",
                    emit: .kirDump,
                    searchPaths: [libDirPath]
                )
                try runSema(ctx)
                assertHasDiagnostic("KSWIFTK-SEMA-SUPER-DEPTH", in: ctx)
            }
        }
    }

    /// A `.kklib` with a 2-cycle (`A : B`, `B : A`) reports the cycle instead
    /// of silently tolerating it.
    @Test
    func testKklibCyclicSupertypesAreRejected() throws {
        let metadata = """
        symbols=2
        class _ fq=evil.A schema=v1 superFq=evil.B
        class _ fq=evil.B schema=v1 superFq=evil.A
        """

        try withKklibDirectory(moduleName: "EvilCycle", metadata: metadata) { libDirPath in
            try withTemporaryFile(contents: "fun main() = 0") { path in
                let ctx = makeCompilationContext(
                    inputs: [path],
                    moduleName: "EvilCycleApp",
                    emit: .kirDump,
                    searchPaths: [libDirPath]
                )
                try runSema(ctx)
                assertHasDiagnostic("KSWIFTK-SEMA-SUPER-CYCLE", in: ctx)
            }
        }
    }

    // MARK: - Fixtures

    /// A bare `SymbolTable` populated with `classCount` classes `lib.N0…`,
    /// so tests exercise `synthesizeNominalLayouts` directly with small,
    /// injected limits instead of paying for a full metadata import.
    private final class NominalChainFixture {
        let interner: StringInterner
        let symbols: SymbolTable
        let types = TypeSystem()
        let classSymbols: [SymbolID]

        init(classCount: Int) {
            let interner = StringInterner()
            let symbols = SymbolTable()
            self.interner = interner
            self.symbols = symbols
            self.classSymbols = (0 ..< classCount).map { index in
                let name = interner.intern("N\(index)")
                return symbols.define(
                    kind: .class,
                    name: name,
                    fqName: [interner.intern("lib"), name],
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .importedLibrary]
                )
            }
        }

        /// `N_i : N_{i+1}` — `classSymbols[0]` is the leaf, so the first
        /// nominal visited by `synthesizeNominalLayouts` descends the entire
        /// chain in a single DFS rather than meeting already-finished bases.
        func chainSupertypes() {
            for index in classSymbols.indices.dropLast() {
                symbols.setDirectSupertypes([classSymbols[index + 1]], for: classSymbols[index])
            }
        }

        /// Give every class one stored field so `instanceFieldCount` exposes
        /// whether bases were laid out first.
        func addFieldPerClass() {
            let lib = interner.intern("lib")
            for index in classSymbols.indices {
                let className = interner.intern("N\(index)")
                let fieldName = interner.intern("f")
                _ = symbols.define(
                    kind: .field,
                    name: fieldName,
                    fqName: [lib, className, fieldName],
                    declSite: nil,
                    visibility: .public
                )
            }
        }
    }

    /// Writes a minimal manifest.json + hand-authored metadata.bin into a
    /// temporary `.kklib` directory (same shape as the manifest tests in
    /// `LibMetadataImportIntegrationTests`).
    private func withKklibDirectory(
        moduleName: String,
        metadata: String,
        body: (String) throws -> Void
    ) throws {
        let fm = FileManager.default
        let libDir = fm.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("kklib")
        defer { try? fm.removeItem(at: libDir) }
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "\(moduleName)",
          "metadata": "metadata.bin"
        }
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        try body(libDir.path)
    }

    /// Runs `body` on a 512 KiB stack — the same budget Swift Testing pool
    /// threads get, per `TypeCheckSemaPhaseLargeStackRegressionTests` — so a
    /// recursive traversal would fault instead of reporting diagnostics.
    private func runOnThinStack(_ body: @escaping () throws -> Void) throws {
        let box = ThinStackWorkBox(body)
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            box.run()
            done.signal()
        }
        thread.stackSize = 512 << 10
        thread.start()
        done.wait()
        try box.result!.get()
    }

    private final class ThinStackWorkBox: @unchecked Sendable {
        let body: () throws -> Void
        var result: Result<Void, any Error>?

        init(_ body: @escaping () throws -> Void) {
            self.body = body
        }

        func run() {
            result = Result(catching: body)
        }
    }
}

#endif
