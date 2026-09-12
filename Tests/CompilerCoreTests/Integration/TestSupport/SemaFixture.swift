#if canImport(Testing)
import Foundation
@testable import CompilerCore
import Testing

/// A suite's Sema run, memoised so the suite's tests share one pipeline
/// execution instead of re-running Sema per test.
///
/// Declare one per suite and route the suite's helpers through it:
///
///     private static let fixture = SemaFixture(surface: "KParameter")
///     private func sharedSema() throws -> (SemaModule, StringInterner) {
///         try Self.fixture.shared()
///     }
///
/// `surface` and `diagnostics` carry the per-suite expectation that a surface
/// resolves cleanly, so a regression reports the offending diagnostics instead
/// of failing later on a nil `ctx.sema`.
///
/// Access is serialised: swift-testing runs a `struct` suite's tests
/// concurrently, so an unsynchronised cache can be read and written at once.
final class SemaFixture: @unchecked Sendable {
    /// How strict a suite is about what Sema reported for its source.
    enum DiagnosticExpectation {
        /// Accept whatever Sema reported; the suite checks the diagnostics itself.
        case unchecked
        /// Fail if Sema reported an error. Warnings are allowed.
        case noErrors
        /// Fail if Sema reported anything at all.
        case noDiagnostics
    }

    private let source: String
    private let surface: String
    private let expectation: DiagnosticExpectation
    private let lock = NSLock()
    private var cached: (SemaModule, StringInterner)?

    init(
        surface: String,
        source: String = "fun noop() {}",
        diagnostics: DiagnosticExpectation = .noErrors
    ) {
        self.surface = surface
        self.source = source
        self.expectation = diagnostics
    }

    /// The suite's shared run, executed on first use and reused afterwards.
    func shared() throws -> (SemaModule, StringInterner) {
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached
        }
        let pair = try make(sources: [source])
        cached = pair
        return pair
    }

    /// A one-off run over `source`, held to the suite's diagnostic expectation.
    func make(source: String) throws -> (SemaModule, StringInterner) {
        try make(sources: [source])
    }

    /// A one-off run over several files compiled as one module.
    func make(sources: [String]) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            check(ctx.diagnostics.diagnostics, hasError: ctx.diagnostics.hasError)
            let sema = try requireTestValue(ctx.sema, "Expected sema module for \(surface) after running Sema")
            result = (sema, ctx.interner)
        }
        return try requireTestValue(result, "Expected \(surface) sema fixture result")
    }

    private func check(_ diagnostics: [Diagnostic], hasError: Bool) {
        switch expectation {
        case .unchecked:
            return
        case .noErrors:
            #expect(
                !hasError,
                Comment(rawValue: "Expected \(surface) surface to resolve cleanly, got: \(describe(diagnostics))")
            )
        case .noDiagnostics:
            #expect(
                diagnostics.isEmpty,
                Comment(rawValue: "Expected \(surface) surface source to compile cleanly, got: \(describe(diagnostics))")
            )
        }
    }

    private func describe(_ diagnostics: [Diagnostic]) -> String {
        diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
    }
}
#endif
