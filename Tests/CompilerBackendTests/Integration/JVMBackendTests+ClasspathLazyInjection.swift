#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func oversizedClasspathFallsBackToReferencedLazyInjection() throws {
        try withWorkspace { root in
            let dependency = try javaFixture(root)

            let eager = try JVMClasspathIndex.load([dependency.path])
            #expect(eager.lazyClassNames.isEmpty)
            #expect(eager.classes["dep/Counter"] != nil)

            let lazy = try JVMClasspathIndex.load(
                [dependency.path], automaticLazyClasspathMemberLimit: 1
            )
            #expect(lazy.classes["dep/Counter"] != nil)
            #expect(lazy.lazyClassNames.contains("dep/Counter"))
            #expect(lazy.lazyClassNames.contains("dep/Child"))
        }
    }
}
#endif
