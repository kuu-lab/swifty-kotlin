@testable import CompilerCore
import TestStdlibCache
import Testing

@Suite(.serialized)
struct PropertyDelegateExtensionScopeExecutionTests {
    @Test(arguments: [0, 2])
    func memberExtensionGetValueInDelegatingClass(optimization: Int) throws {
        TestStdlibCache.shared.prepare()
        let source = """
        import kotlin.reflect.KProperty

        class Delegate {
        }

        class A {
            operator fun Delegate.getValue(t: Any?, p: KProperty<*>): Int = 1
            val prop: Int by Delegate()
        }

        fun box(): String {
            return if (A().prop == 1) "OK" else "fail"
        }

        fun main() {
            print(box())
        }
        """
        try compileAndRunKotlinSources(
            [source],
            expectedOutput: "OK", moduleName: "KUU2135MemberExtensionDelegate",
            allowDefaultStdlibLibrary: true,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: "", requireNoCompilerDiagnostics: true
        )
    }

    @Test(arguments: [0, 2])
    func lazyWithoutShadowingExtensions(optimization: Int) throws {
        TestStdlibCache.shared.prepare()
        try compileAndRunKotlinSources(
            [diffCaseSource("lazy_shadow_control.kt")],
            expectedOutput: "true\n", moduleName: "KUU2008UnshadowedLazyControl",
            allowDefaultStdlibLibrary: true,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: "", requireNoCompilerDiagnostics: true
        )
    }

    @Test(arguments: [false, true], [0, 2])
    func inapplicableMemberExtensionDoesNotHideLazy(useArtifact: Bool, optimization: Int) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        try compileAndRunKotlinSources(
            [diffCaseSource("lazy_delegate_inapplicable_member_extension.kt")],
            expectedOutput: "true\n", moduleName: "KUU2008LazyDelegate",
            allowDefaultStdlibLibrary: useArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: "", requireNoCompilerDiagnostics: true
        )
    }

    @Test(arguments: [false, true], [0, 2])
    func applicableMembersWinAndInapplicableScopesFallThrough(useArtifact: Bool, optimization: Int) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        try compileAndRunKotlinSources(
            [diffCaseSource("lazy_delegate_extension_scope_controls.kt")],
            expectedOutput: "true\n41\n42\n42\n43\n", moduleName: "KUU2008DelegateControls",
            allowDefaultStdlibLibrary: useArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: "", requireNoCompilerDiagnostics: true
        )
    }
}
