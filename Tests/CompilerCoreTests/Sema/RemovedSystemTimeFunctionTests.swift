@testable import CompilerCore
import Testing

/// KUU-1263/KUU-1468: clock getters unavailable in Kotlin/JVM must not resolve through bundled source.
@Suite
struct RemovedSystemTimeFunctionTests {
    @Test
    func removedFunctionsAreUnresolvedForAllImportStyles() throws {
        let names = ["getTimeMillis", "getTimeMicros", "getTimeNanos"]
        let styles = ["explicit", "wildcard", "alias", "qualified"]
        var sources: [String] = []
        var callNames: [String] = []
        for name in names {
            for style in styles {
                let declaration: String
                let callName: String
                switch style {
                case "explicit":
                    declaration = "import kotlin.system.\(name)\nfun now(): Long = \(name)()"
                    callName = name
                case "wildcard":
                    declaration = "import kotlin.system.*\nfun now(): Long = \(name)()"
                    callName = name
                case "alias":
                    declaration = "import kotlin.system.\(name) as removedClock\nfun now(): Long = removedClock()"
                    callName = "removedClock"
                default:
                    declaration = "fun now(): Long = kotlin.system.\(name)()"
                    callName = ""
                }
                sources.append("package probe\(sources.count)\n" + declaration)
                callNames.append(callName)
            }
        }
        // Compile the bundled stdlib once while keeping each import scope isolated.
        let ctx = makeContextFromSources(sources)
        do {
            try runSema(ctx)
        } catch {
            // Sema reports errors before throwing; assert each file's failure below.
        }
        for (index, callName) in callNames.enumerated() {
            #expect(ctx.diagnostics.diagnostics.contains {
                guard $0.severity == .error, let range = $0.primaryRange else { return false }
                return ctx.sourceManager.path(of: range.start.file).hasSuffix("/input\(index).kt")
                    && ["KSWIFTK-SEMA-0022", "KSWIFTK-SEMA-0023"].contains($0.code)
                    && $0.message.contains("Unresolved")
                    && (callName.isEmpty || $0.message.contains("'\(callName)'"))
            }, "Expected unresolved removed API in input\(index), got: \(ctx.diagnostics.diagnostics)")
        }
        let sema = try #require(ctx.sema)
        for name in names {
            let fq = ["kotlin", "system", name].map { ctx.interner.intern($0) }
            #expect(sema.symbols.lookupAll(fqName: fq).isEmpty)
        }
    }

    @Test
    func wildcardImportStillAllowsUserDefinedClockFunctions() throws {
        let ctx = makeContextFromSource("""
        import kotlin.system.*
        fun getTimeMillis(): Long = 1L
        fun getTimeMicros(): Long = 2L
        fun getTimeNanos(): Long = 2L
        fun now(): Long = getTimeMillis() + getTimeMicros() + getTimeNanos()
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError)
    }
}
