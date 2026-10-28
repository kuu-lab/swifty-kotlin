#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct AssociatePrivateSubclassPairInferenceTests {
    private func semaErrors(_ source: String, allowDefaultStdlibLibrary: Bool = false) throws -> [String] {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        let ctx = makeContextFromSource(source, emit: .executable, allowDefaultStdlibLibrary: allowDefaultStdlibLibrary)
        if allowDefaultStdlibLibrary { #expect(ctx.options.stdlibLibraryPath != nil) }
        try runSema(ctx)
        return ctx.diagnostics.diagnostics
            .filter { $0.severity == .error }
            .map { "\($0.code): \($0.message)" }
    }

    @Test(arguments: [false, true])
    func unrelatedAssociateValuesStillJoinToAny(allowDefaultStdlibLibrary: Bool) throws {
        let errors = try semaErrors("""
        class Solver {
            private abstract class Module(val name: String)
            private class A : Module("a")
            private class Other(val label: String)

            fun probe(flag: Boolean): String {
                val modules = listOf(flag).associate {
                    if (it) "module" to A() else "other" to Other("other")
                }
                return modules.values.joinToString { it.name }
            }
        }
        """, allowDefaultStdlibLibrary: allowDefaultStdlibLibrary)
        #expect(
            errors.contains { $0.contains("Unresolved") && $0.contains("'name'") },
            "Unrelated values must not gain Module.name: \(errors)"
        )
    }
}
#endif
