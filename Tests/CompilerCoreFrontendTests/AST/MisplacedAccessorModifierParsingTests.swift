#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct MisplacedAccessorModifierParsingTests {
    @Test(arguments: [
        "class C { private set var x = 1 }",
        "class C { private get var x = 1 }",
        "class C { internal set val x = 1 }",
        "class C { protected set var x = 1 }",
        "private set var x = 1",
    ])
    func rejectsGetSetAfterModifierPrefix(_ source: String) throws {
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)
        let diagnostics = context.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-PARSE-0002" && $0.message == "Expecting member declaration."
        }

        #expect(diagnostics.count >= 1)
        #expect(diagnostics.first?.severity == .error)
    }

    @Test
    func trailingAccessorAfterPropertyStaysValid() throws {
        let source = """
        class C {
            var x = 1
                private set
        }
        """
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)

        assertNoDiagnostic("KSWIFTK-PARSE-0002", in: context)
        #expect(!context.diagnostics.hasError)
    }

    @Test
    func customGetSetAccessorsStayValid() throws {
        let source = """
        class C {
            var x = 1
                get() = 2
                set(v) { field = v }
        }
        """
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)

        assertNoDiagnostic("KSWIFTK-PARSE-0002", in: context)
        #expect(!context.diagnostics.hasError)
    }

    @Test(arguments: [
        "val set = 1",
        "var get = 2",
        "class C { private val set = 1 }",
        "class C { var get = 2 }",
        "fun set() {}",
    ])
    func getSetAsDeclarationNameStaysValid(_ source: String) throws {
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)

        assertNoDiagnostic("KSWIFTK-PARSE-0002", in: context)
    }
}
#endif
