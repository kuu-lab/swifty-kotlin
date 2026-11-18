#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func explicitGetterReturnTypesExecuteOnJVM(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            class WikiSite(val name: String)
            class ActivityTabViewModel {
                val wikiSiteForTimeline get(): WikiSite {
                    return WikiSite("timeline")
                }
                val answer get(): Int = 42
            }
            val Int.isStarted get(): Boolean {
                return this > 0
            }
            var maybe get(): String? { return null } set(value) {}
            fun main() {
                println(ActivityTabViewModel().wikiSiteForTimeline.name)
                println(ActivityTabViewModel().answer)
                println(1.isStarted)
                maybe = null
                println(maybe)
            }
            """, expected: "timeline\n42\ntrue\nnull\n", mode: mode, root: root)
        }
    }
}
#endif
