import Foundation
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct InferenceReuseAfterUnrelatedErrorTests {
    @Test(arguments: [false, true], ["first()", "choose(first(), first())"])
    func recursiveDependencyDiagnosticSurvivesSpeculativeMemberCheck(
        declarationFirst: Bool, call: String
    ) throws {
        let caller = "class Caller { fun call() = \(call) }"
        let declarations = """
        fun choose(a: Any, b: Any): Any = a
        fun first() = second()
        fun second() = first()
        """
        let source = declarationFirst ? declarations + "\n" + caller : caller + "\n" + declarations
        let input = "/virtual/recursive-inference.kt"
        let context = makeCompilationContext(inputs: [input], includeStdlib: false)
        _ = context.sourceManager.addFile(path: input, contents: Data(source.utf8))
        try runSema(context)
        #expect(context.diagnostics.diagnostics.contains {
            $0.severity == .error && $0.code == "KSWIFTK-SEMA-INFER"
        })
    }

    // `.timeLimit` requires macOS 13+; the package floor is macOS 12, so the
    // trait expression must be type-checked under a macOS 13 context. On older
    // hosts the test is skipped; Linux and macOS 13+ run it normally.
    @available(macOS 13.0, *)
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func sharedInferredDependenciesRemainBoundedAfterUnrelatedHeaderError(memberProperty: Bool) throws {
        let brokenPath = "/virtual/unrelated-header.kt"
        let healthyPath = "/virtual/shared-inference.kt"
        let context = makeCompilationContext(inputs: [brokenPath, healthyPath], includeStdlib: false)
        _ = context.sourceManager.addFile(
            path: brokenPath, contents: Data("fun unrelated(value: Missing) {}".utf8)
        )
        let functions = (1...28).reversed().map { level in
            let dependency = level == 1 ? "leaf" : "level\(level - 1)"
            return "fun level\(level)() = \(dependency)() + \(dependency)()"
        }.joined(separator: "\n") + "\nfun leaf() = \(memberProperty ? "base" : "1")"
        let source = memberProperty ? "class Shared { val base = 1\n\(functions)\n}" : functions
        _ = context.sourceManager.addFile(path: healthyPath, contents: Data(source.utf8))
        try runSema(context)

        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(!errors.isEmpty)
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0025" && $0.message.contains("Missing") })
        let sema = try #require(context.sema)
        let rootName = (memberProperty ? ["Shared", "level28"] : ["level28"]).map(context.interner.intern)
        let root = try #require(sema.symbols.lookup(fqName: rootName))
        #expect(sema.symbols.functionSignature(for: root)?.returnType == sema.types.intType)
    }

    @Test(arguments: [false, true])
    func failingPropertyStillReportsItsOwnDiagnostic(declarationFirst: Bool) throws {
        let caller = "fun read() = value"
        let declaration = "val value = missing()"
        let members = declarationFirst ? declaration + "\n" + caller : caller + "\n" + declaration
        let input = "/virtual/failing-property-inference.kt"
        let context = makeCompilationContext(inputs: [input], includeStdlib: false)
        _ = context.sourceManager.addFile(path: input, contents: Data("class Holder {\n\(members)\n}".utf8))
        try runSema(context)
        #expect(context.diagnostics.diagnostics.contains {
            $0.severity == .error && $0.message.contains("missing")
        })
    }

    @Test
    func repeatedRecursivePropertyDependencyStillReportsError() throws {
        let input = "/virtual/recursive-property-inference.kt"
        let context = makeCompilationContext(inputs: [input], includeStdlib: false)
        _ = context.sourceManager.addFile(path: input, contents: Data("""
        class Caller { fun call() = choose(first, first) }
        fun choose(a: Any?, b: Any?): Any? = a
        val first = second
        val second = first
        """.utf8))
        try runSema(context)
        #expect(context.diagnostics.diagnostics.contains {
            $0.severity == .error && $0.message.contains("Recursive")
        })
    }

    @Test(arguments: [false, true])
    func failingDependencyStillReportsItsOwnDiagnostic(declarationFirst: Bool) throws {
        let caller = "fun caller() = broken()"
        let declaration = "fun broken() = missing()"
        let source = declarationFirst ? declaration + "\n" + caller : caller + "\n" + declaration
        let input = "/virtual/failing-inference.kt"
        let context = makeCompilationContext(inputs: [input], includeStdlib: false)
        _ = context.sourceManager.addFile(path: input, contents: Data(source.utf8))
        try runSema(context)
        #expect(context.diagnostics.diagnostics.contains {
            $0.severity == .error && $0.message.contains("missing")
        })
    }
}
