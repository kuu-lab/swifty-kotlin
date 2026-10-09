#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

@Suite
struct CoroutineOptInMarkerTests {
    private let markerNames = [
        "kotlinx.coroutines.DelicateCoroutinesApi",
        "kotlinx.coroutines.FlowPreview",
        "kotlinx.coroutines.ObsoleteCoroutinesApi",
        "kotlinx.coroutines.InternalCoroutinesApi",
        "kotlinx.coroutines.ExperimentalCoroutinesApi",
    ]

    private let unoptedSource = """
    import kotlinx.coroutines.*
    import kotlinx.coroutines.channels.*
    import kotlinx.coroutines.flow.*
    import kotlin.time.DurationUnit
    import kotlin.time.toDuration

    fun useDelicate() { GlobalScope.launch { } }
    fun useFlowPreview() {
        flowOf(1).debounce(1L)
        flowOf(1).sample(1L)
        flowOf(1).sample(1.toDuration(DurationUnit.MILLISECONDS))
    }
    fun useObsolete(scope: CoroutineScope) { scope.actor<Int> { } }
    fun useActorScope(scope: ActorScope<Int>) { scope.channel }
    suspend fun useInternal(c: CancellableContinuation<Int>) {
        val token = c.tryResume(7)
        if (token != null) c.completeResume(token)
        c.tryResumeWithException(IllegalStateException())
    }
    suspend fun useStableCollectLatest() {
        flowOf(1).buffer().flowOn(Dispatchers.Default).collectLatest { }
    }
    """

    private let optedInSource = """
    import kotlinx.coroutines.*
    import kotlinx.coroutines.channels.*
    import kotlinx.coroutines.flow.*
    import kotlin.time.DurationUnit
    import kotlin.time.toDuration

    @OptIn(DelicateCoroutinesApi::class)
    fun useDelicate() { GlobalScope.launch { } }
    @OptIn(FlowPreview::class)
    fun useFlowPreview() {
        flowOf(1).debounce(1L)
        flowOf(1).sample(1L)
        flowOf(1).sample(1.toDuration(DurationUnit.MILLISECONDS))
    }
    @OptIn(ObsoleteCoroutinesApi::class)
    fun useObsolete(scope: CoroutineScope) { scope.actor<Int> { } }
    @OptIn(ObsoleteCoroutinesApi::class)
    fun useActorScope(scope: ActorScope<Int>) { scope.channel }
    @OptIn(InternalCoroutinesApi::class)
    suspend fun useInternal(c: CancellableContinuation<Int>) {
        val token = c.tryResume(7)
        if (token != null) c.completeResume(token)
        c.tryResumeWithException(IllegalStateException())
    }
    suspend fun useStableCollectLatest() { flowOf(1).collectLatest { } }
    """

    @Test
    func upstreamLevelsAreReportedFromBundledSource() {
        let sourceContext = semaContext(unoptedSource, usingFreshKklib: false)
        let allOptInDiagnostics = userOptInDiagnostics(in: sourceContext)
        let delicate = matchingDiagnostics(for: markerNames[0], in: allOptInDiagnostics)
        #expect(delicate.count == 1, "Expected GlobalScope to require DelicateCoroutinesApi: \(allOptInDiagnostics)")
        #expect(delicate.allSatisfy { $0.severity == .warning })

        let flowPreview = matchingDiagnostics(for: markerNames[1], in: allOptInDiagnostics)
        #expect(flowPreview.count == 3, "Expected canonical debounce and both sample overloads to require FlowPreview: \(allOptInDiagnostics)")
        #expect(flowPreview.allSatisfy { $0.severity == .warning })

        let obsolete = matchingDiagnostics(for: markerNames[2], in: allOptInDiagnostics)
        #expect(obsolete.count >= 2, "Expected actor and ActorScope to require ObsoleteCoroutinesApi: \(allOptInDiagnostics)")
        #expect(obsolete.allSatisfy { $0.severity == .warning })

        let internalApi = matchingDiagnostics(for: markerNames[3], in: allOptInDiagnostics)
        #expect(internalApi.count == 3, "Expected all three continuation helpers to require opt-in: \(allOptInDiagnostics)")
        #expect(internalApi.allSatisfy { $0.severity == .error })
        #expect(!allOptInDiagnostics.contains { $0.message.contains(markerNames[4]) },
                "collectLatest is stable and must not require ExperimentalCoroutinesApi: \(allOptInDiagnostics)")

        let bundledOptInDiagnostics = sourceContext.diagnostics.diagnostics.filter { diagnostic in
            diagnostic.code == "KSWIFTK-SEMA-OPT-IN"
                && diagnostic.primaryRange.map {
                    sourceContext.sourceManager.origin(of: $0.start.file)?.isBundledStdlib == true
                } == true
        }
        #expect(bundledOptInDiagnostics.isEmpty,
                "Bundled coroutine implementations must opt in to their own restricted calls: \(bundledOptInDiagnostics)")
    }

    @Test
    func explicitOptInAcceptsRestrictedCoroutinesApisFromSourceAndFreshKklib() {
        for useFreshKklib in [false, true] {
            let context = semaContext(optedInSource, usingFreshKklib: useFreshKklib)
            #expect(userOptInDiagnostics(in: context).isEmpty,
                    "Explicit @OptIn should suppress coroutines diagnostics: \(context.diagnostics.diagnostics)")
        }
    }

    @Test
    func aliasedDebounceMatchesCanonicalOptInDiagnosticsFromSourceAndFreshKklib() {
        let canonicalSource = """
        import kotlinx.coroutines.flow.*
        fun useFlowPreview() { flowOf(1).debounce(1L) }
        """
        let aliasedSource = """
        import kotlinx.coroutines.flow.*
        import kotlinx.coroutines.flow.debounce as delayed
        fun useFlowPreview() { flowOf(1).delayed(1L) }
        """

        for useFreshKklib in [false, true] {
            let canonicalContext = semaContext(canonicalSource, usingFreshKklib: useFreshKklib)
            let aliasedContext = semaContext(aliasedSource, usingFreshKklib: useFreshKklib)
            let canonicalDiagnostics = matchingDiagnostics(
                for: markerNames[1],
                in: userOptInDiagnostics(in: canonicalContext)
            )
            let aliasedDiagnostics = matchingDiagnostics(
                for: markerNames[1],
                in: userOptInDiagnostics(in: aliasedContext)
            )

            #expect(canonicalDiagnostics.count == 1,
                    "Canonical debounce should report exactly one FlowPreview warning: \(canonicalDiagnostics)")
            #expect(canonicalDiagnostics.allSatisfy { $0.severity == .warning })
            #expect(aliasedDiagnostics.count == 1,
                    "Aliased debounce should report exactly one FlowPreview warning: \(aliasedDiagnostics)")
            #expect(aliasedDiagnostics.allSatisfy { $0.severity == .warning })
            #expect(diagnosticSignatures(canonicalDiagnostics) == diagnosticSignatures(aliasedDiagnostics),
                    "Import aliases should preserve FlowPreview marker and severity")
        }
    }

    @Test
    func optInMarkerDiagnosticsSurviveFreshKklibMetadataRoundTrip() {
        let sourceContext = semaContext(unoptedSource, usingFreshKklib: false)
        let artifactContext = semaContext(unoptedSource, usingFreshKklib: true)
        let sourceDiagnostics = userOptInDiagnostics(in: sourceContext)
        let artifactDiagnostics = userOptInDiagnostics(in: artifactContext)

        #expect(diagnosticSignatures(sourceDiagnostics) == diagnosticSignatures(artifactDiagnostics),
                "Fresh .kklib metadata must preserve the source marker/severity diagnostics")
        let nonUserErrors = artifactContext.diagnostics.diagnostics.filter { diagnostic in
            let isExpectedUserOptInError = diagnostic.code == "KSWIFTK-SEMA-OPT-IN"
                && diagnostic.primaryRange.map {
                    artifactContext.sourceManager.origin(of: $0.start.file) == .user
                } == true
            return diagnostic.severity == .error && !isExpectedUserOptInError
        }
        #expect(nonUserErrors.isEmpty,
                "Only the expected user-facing InternalCoroutinesApi errors should remain: \(nonUserErrors)")
    }

    private func semaContext(_ source: String, usingFreshKklib: Bool) -> CompilationContext {
        if usingFreshKklib {
            TestStdlibCache.shared.prepare()
            let artifactPath = CompilerOptions.defaultStdlibLibraryPath ?? ""
            #expect(FileManager.default.fileExists(atPath: artifactPath),
                    "TestStdlibCache should produce a fresh bundled .kklib before importing it")
        }
        let context = makeContextFromSource(source, allowDefaultStdlibLibrary: usingFreshKklib)
        do {
            try runSema(context)
        } catch {
            // Expected in the unopted source: InternalCoroutinesApi uses are errors.
        }
        return context
    }

    private func userOptInDiagnostics(in context: CompilationContext) -> [Diagnostic] {
        context.diagnostics.diagnostics.filter { diagnostic in
            diagnostic.code == "KSWIFTK-SEMA-OPT-IN"
                && diagnostic.primaryRange.map {
                    context.sourceManager.origin(of: $0.start.file) == .user
                } == true
        }
    }

    private func matchingDiagnostics(for marker: String, in diagnostics: [Diagnostic]) -> [Diagnostic] {
        diagnostics.filter { $0.message.contains(marker) }
    }

    private func diagnosticSignatures(_ diagnostics: [Diagnostic]) -> [String] {
        diagnostics.map { diagnostic in
            let marker = markerNames.first { diagnostic.message.contains($0) } ?? "unknown marker"
            return "\(marker)|\(diagnostic.severity)"
        }.sorted()
    }
}
#endif
