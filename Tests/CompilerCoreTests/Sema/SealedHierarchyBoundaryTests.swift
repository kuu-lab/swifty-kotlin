@testable import CompilerCore
import Foundation
import Testing

@Suite
struct SealedHierarchyBoundaryTests {
    @Test(arguments: ["same", "external"])
    func checksNestedAndCompanionSubclassesUsingActualPackage(packageName: String) {
        let basePath = "/tmp/sealed-base-\(UUID().uuidString).kt"
        let childPath = "/tmp/sealed-child-\(UUID().uuidString).kt"
        let options = CompilerOptions(moduleName: "Sealed", inputs: [basePath, childPath], outputPath: "/tmp/sealed",
                                      emit: .executable, target: defaultTargetTriple(), includeStdlib: false)
        let context = CompilerDriver().runFrontend(options: options, inMemorySources: [
            basePath: Data("package same\nsealed class Base".utf8),
            childPath: Data("""
            package \(packageName)
            import same.Base
            class Holder { class Nested: Base(); companion object { class CompanionNested: Base() } }
            interface Owner { class Nested: Base(); companion object { class CompanionNested: Base() } }
            object Singleton { class Nested: Base() }
            """.utf8),
        ]).context
        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == (packageName == "same" ? 0 : 5), "\(errors)")
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0070" && $0.message.contains("same package") })
    }
}
