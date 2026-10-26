@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct BundledClassifierImportScopeTests {
    @Test(arguments: [
        ("fun probe() = Factory.value()", true),
        ("import java.util.Factory\nfun probe() = Factory.value()", false),
        ("import java.util.*\nfun probe() = Factory.value()", false),
        ("import java.util.Factory as Alias\nfun probe() = Alias.value()", false),
        ("fun probe() = java.util.Factory.value()", false),
        ("package java.util\nfun probe() = Factory.value()", false),
        ("object Factory { fun value(): Int = 9 }; fun probe() = Factory.value()", false),
    ])
    func bundledClassifierRequiresFileScopeVisibility(source: String, rejects: Bool) throws {
        let user = "/tmp/import-user-\(UUID().uuidString).kt"
        let bundled = "/tmp/import-bundled-\(UUID().uuidString).kt"
        let context = makeCompilationContext(inputs: [user, bundled], includeStdlib: false)
        _ = context.sourceManager.addFile(path: user, contents: Data(source.utf8))
        _ = context.sourceManager.addFile(path: bundled, contents: Data("""
        package java.util
        class Factory { companion object { fun value(): Int = 7 } }
        """.utf8), origin: .bundledStdlib)
        try runSema(context)
        #expect(context.diagnostics.hasError == rejects, "\(context.diagnostics.diagnostics)")
    }
}
