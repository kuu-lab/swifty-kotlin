#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct SafeLetGenericElvisInferenceTests {
    @Test(arguments: [false, true])
    func genericSafeLetResultJoinsWithElvisFallbackTypeParameter(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        let sources = [
            """
            package safeLetElvisGenericResult
            interface Enc<T> {
                fun decode(name: String, value: String): T
                fun empty(name: String): T
            }
            abstract class At<T>(val encoder: Enc<T>) {
                open operator fun get(m: MutableMap<String, String>, name: String): T =
                    m[name]?.let { encoder.decode(name, it) } ?: encoder.empty(name)
            }
            """,
            """
            package safeLetElvisUnrelatedTypes
            fun <T> reject(value: String?, fallback: T): T = value ?: fallback
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: useArtifact ? .executable : .kirDump,
                allowDefaultStdlibLibrary: useArtifact
            )
            if useArtifact {
                #expect(ctx.options.stdlibLibraryPath != nil)
            }
            try runSema(ctx)
            let positiveDiagnostics = diagnosticsForPath(paths[0], in: ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: positiveDiagnostics)
            #expect(positiveDiagnostics.filter { $0.severity == .error }.isEmpty,
                    "got: \(positiveDiagnostics.filter { $0.severity == .error }.map { "\($0.code): \($0.message)" })")
            assertHasDiagnostic("KSWIFTK-TYPE-0001", in: diagnosticsForPath(paths[1], in: ctx))
        }
    }
}
#endif
