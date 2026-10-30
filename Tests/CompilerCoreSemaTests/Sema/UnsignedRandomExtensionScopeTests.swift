#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct UnsignedRandomExtensionScopeTests {
    private let declarations = """
    package kotlin.random
    open class Random {
        fun nextInt(): Int = 1
        fun nextLong(): Long = 1L
        companion object Default : Random()
    }
    fun Random.nextUInt(): UInt = 1u
    fun Random.nextULong(): ULong = 1uL
    """

    @Test
    func bundledUnsignedExtensionsHonorImportsOnInstancesAndCompanions() throws {
        for receiver in ["random", "Random", "Random.Default"] {
            for imports in [
                "import kotlin.random.Random",
                "import kotlin.random.*",
                "import kotlin.random.Random\nimport kotlin.random.nextUInt\nimport kotlin.random.nextULong",
                "import kotlin.random.Random\nimport kotlin.random.nextUInt as uintBits\nimport kotlin.random.nextULong as ulongBits",
            ] {
                let alias = imports.contains("as uintBits")
                let source = """
                \(imports)
                fun use(random: Random) {
                    val a: UInt = \(receiver).\(alias ? "uintBits" : "nextUInt")()
                    val b: ULong = \(receiver).\(alias ? "ulongBits" : "nextULong")()
                }
                """
                try withTemporaryFile(contents: source) { path in
                    let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
                    _ = ctx.sourceManager.addFile(
                        path: "__bundled_unsigned_random.kt", contents: Data(declarations.utf8), origin: .bundledStdlib
                    )
                    do { try runSema(ctx) } catch { }
                    let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
                    if imports == "import kotlin.random.Random" {
                        #expect(errors.count == 2, "\(receiver): \(errors)")
                        #expect(errors.allSatisfy { $0.message.contains("Unresolved") })
                    } else {
                        #expect(errors.isEmpty, "\(receiver), \(imports): \(errors)")
                    }
                }
            }
        }
    }

    @Test
    func aliasDoesNotExposeOriginalNamesAndSignedMembersNeedNoImport() throws {
        let source = """
        import kotlin.random.Random
        import kotlin.random.nextUInt as uintBits
        import kotlin.random.nextULong as ulongBits
        fun use(random: Random) {
            random.nextInt()
            random.nextLong()
            random.uintBits()
            random.ulongBits()
            random.nextUInt()
            random.nextULong()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            _ = ctx.sourceManager.addFile(
                path: "__bundled_unsigned_random.kt", contents: Data(declarations.utf8), origin: .bundledStdlib
            )
            do { try runSema(ctx) } catch { }
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 2, "\(errors)")
            #expect(errors.allSatisfy { $0.message.contains("Unresolved") })
        }
    }
}
#endif
