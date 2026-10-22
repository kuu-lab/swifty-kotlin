import Foundation

func runFrontendSyntaxPhases(_ context: CompilationContext) throws {
    try LoadSourcesPhase().run(context)
    try LexPhase().run(context)
    try ParsePhase().run(context)
    try BuildASTPhase().run(context)
}

public enum FrontendContinuationPolicy: Sendable {
    case stopOnError

    case continueAfterParseError
}

public struct FrontendResult {
    public let context: CompilationContext
    public let diagnostics: [Diagnostic]

    public init(context: CompilationContext, diagnostics: [Diagnostic]) {
        self.context = context
        self.diagnostics = diagnostics
    }
}

public extension CompilerDriver {
    /// Intended for language-server / editor integrations that need
    /// diagnostics and semantic information for open buffers.
    ///
    /// - Parameters:
    ///   - inMemorySources: Optional map of file path → source bytes for unsaved
    ///     editor buffers. Each entry is pre-seeded into the `SourceManager`, so
    ///     `LoadSourcesPhase` (which skips already-registered paths) uses the
    ///     in-memory contents instead of reading from disk.
    ///   - continuationPolicy: The default preserves the fail-fast frontend
    ///     behavior.
    func runFrontend(
        options: CompilerOptions,
        inMemorySources: [String: Data] = [:],
        continuationPolicy: FrontendContinuationPolicy = .stopOnError
    ) -> FrontendResult {
        let context = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: KklibSemaSession.makeInterner(options: options) ?? StringInterner()
        )

        for (path, data) in inMemorySources {
            _ = context.sourceManager.addFile(path: path, contents: data)
        }

        let phases: [CompilerPhase] = [LoadSourcesPhase()]
            + (options.emit.isJVM ? [JVMPreparationPhase()] : []) + [
            LexPhase(),
            ParsePhase(rejectsTopLevelStatementsOutsideScripts: true),
            BuildASTPhase(),
        ] + (options.emit.isJVM ? [JVMSourceValidationPhase(), SemaPhase(), JVMFrontendPhase()] : [SemaPhase()])

        var continuedAfterParseError = false
        for phase in phases {
            do {
                try phase.run(context)
            } catch {
                if !context.diagnostics.hasError {
                    if let fallback = Self.fallbackDiagnostic(for: error) {
                        context.diagnostics.error(fallback.code, fallback.message, range: nil)
                    } else {
                        context.diagnostics.error(
                            "KSWIFTK-ICE-0001",
                            "Compiler internal error: \(error)",
                            range: nil
                        )
                    }
                }
                break
            }
            if continuationPolicy == .continueAfterParseError,
               phase is ParsePhase,
               context.diagnostics.hasError
            {
                continuedAfterParseError = true
            }

            // The LSP policy allows Parse to hand its recovered syntax tree to
            // BuildAST and Sema. Other frontend errors, and the default policy,
            // retain the fail-fast behavior.
            if context.diagnostics.hasError {
                if !continuedAfterParseError {
                    break
                }
            }
        }

        context.diagnostics.sortBySourceLocation()
        return FrontendResult(context: context, diagnostics: context.diagnostics.diagnostics)
    }
}
