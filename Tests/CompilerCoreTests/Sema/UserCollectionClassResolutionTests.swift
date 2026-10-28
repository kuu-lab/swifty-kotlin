@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct UserCollectionClassResolutionTests {
    /// KUU-1939: an invisible user constructor must not fall back to a stdlib constructor.
    @Test(arguments: ["HashSet", "LinkedHashSet", "HashMap", "LinkedHashMap"])
    func privateUserCollectionConstructorRemainsInvisible(name: String) throws {
        let parameters = name.hasSuffix("Set") ? "T" : "K, V"
        let arguments = name.hasSuffix("Set") ? "Int" : "String, Int"
        try withTemporaryFile(contents: """
        package mypkg
        class \(name)<\(parameters)> private constructor()
        fun make() = \(name)<\(arguments)>()
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains {
                $0.severity == .error && $0.code == "KSWIFTK-SEMA-0040"
            }, "Expected inaccessible user constructor: \(ctx.diagnostics.diagnostics)")
        }
    }
}
