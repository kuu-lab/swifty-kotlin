@testable import CompilerBackend
@testable import KSwiftKCLI
import Testing

@Suite
struct CLICachedStdlibTests {
    @Test
    func distinguishesIdentityFallbackFromBuildFailure() {
        var output: [String] = []
        var errors: [String] = []
        let success = CLIApplication.resolveCachedStdlib(
            resolve: { "/tmp/stdlib.kklib" },
            writeOutput: { output.append($0) }, writeError: { errors.append($0) }
        )
        #expect(success == 0)
        #expect(output == ["/tmp/stdlib.kklib"])
        #expect(errors.isEmpty)

        let unavailable = CLIApplication.resolveCachedStdlib(
            resolve: { throw DiffStdlibCache.Error.fingerprintUnavailable },
            writeOutput: { output.append($0) }, writeError: { errors.append($0) }
        )
        #expect(unavailable == 2)
        #expect(errors.last?.contains("identity unavailable") == true)

        let failed = CLIApplication.resolveCachedStdlib(
            resolve: { throw DiffStdlibCache.Error.inputsChangedDuringBuild },
            writeOutput: { output.append($0) }, writeError: { errors.append($0) }
        )
        #expect(failed == 1)
        #expect(errors.last?.contains("inputs changed during the build") == true)
        #expect(output.count == 1)
    }

    @Test
    func helpAdvertisesTheCacheProtocol() {
        #expect(CLIParser.usageText.contains("--cached-stdlib-path"))
    }
}
