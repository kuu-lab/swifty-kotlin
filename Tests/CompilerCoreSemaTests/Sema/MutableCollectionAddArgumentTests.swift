@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct MutableCollectionAddArgumentTests {
    @Test(arguments: ["MutableSet", "MutableList", "MutableCollection"])
    func insertionKeepsElementTypeAndNullability(collection: String) throws {
        let sources = [
            "fun bad(values: \(collection)<String>) { values.add(null) }",
            "fun bad(values: \(collection)<String>) { values.add(1) }",
            "fun good(values: \(collection)<String?>) { values.add(null) }",
            "fun <E> good(values: \(collection)<E>, value: E) { values.add(value) }",
        ]
        for (index, source) in sources.enumerated() {
            let support = collection == "MutableSet"
                ? "package kotlin.collections; interface MutableSet<E> : MutableCollection<E>"
                : ""
            try withTemporaryFiles(contents: [support, source]) { paths in
                let context = makeCompilationContext(inputs: paths, includeStdlib: false)
                try runSema(context)
                #expect(!context.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0025" })
                #expect(context.diagnostics.hasError == (index < 2), "\(source): \(context.diagnostics.diagnostics)")
            }
        }
    }
}
