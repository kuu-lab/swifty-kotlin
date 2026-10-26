#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ImplicitImportParityTests {
    @Test
    func reflectionAndSystemImportsAreRequired() throws {
        let ctx = makeContextFromSources([
            "fun missingReflect(): KClass<*> = Int::class",
            "import kotlin.reflect.KClass\nfun explicitReflect(): KClass<*> = Int::class",
            "fun missingSystem(): Nothing = exitProcess(0)",
            "import kotlin.system.exitProcess\nfun explicitSystem(): Nothing = exitProcess(0)",
        ])
        do { try runSema(ctx) } catch {}

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        func fileErrors(in inputIndex: Int) -> [Diagnostic] {
            errors.filter {
                guard let range = $0.primaryRange else { return false }
                return ctx.sourceManager.path(of: range.start.file).hasSuffix("/input\(inputIndex).kt")
            }
        }
        let missingReflectErrors = fileErrors(in: 0)
        let explicitReflectErrors = fileErrors(in: 1)
        let missingSystemErrors = fileErrors(in: 2)
        let explicitSystemErrors = fileErrors(in: 3)
        #expect(missingReflectErrors.contains {
            $0.message.contains("KClass") && $0.message.contains("Unresolved")
        }, "\(errors)")
        #expect(explicitReflectErrors.isEmpty, "An explicit KClass import should resolve: \(explicitReflectErrors)")
        #expect(missingSystemErrors.contains {
            $0.message.contains("exitProcess") && $0.message.contains("Unresolved")
        }, "\(errors)")
        #expect(explicitSystemErrors.isEmpty, "An explicit exitProcess import should resolve: \(explicitSystemErrors)")
    }
}
#endif
