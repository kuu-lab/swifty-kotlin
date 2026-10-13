@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Testing
import TestStdlibCache

@Suite
struct CodegenLinkedHashSetHierarchyTests {
    @Test(arguments: [false, true])
    func linkedHashSetSubtypeAndErasedCasts(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        let source = """
        class Tags : LinkedHashSet<Int>()
        class HashTags : HashSet<Int>()

        fun main() {
            val lhs = LinkedHashSet<Int>()
            lhs.add(1)
            println(lhs is HashSet<Int>)
            val viaSub: HashSet<Int> = lhs
            println(viaSub.size)

            val erased: Any = lhs
            println(erased is HashSet<*>)
            println(erased is AbstractMutableSet<*>)
            val cast = erased as HashSet<Int>
            cast.add(2)
            println(lhs.joinToString())
            println((erased as? HashSet<Int>)?.size)

            val plain: Any = HashSet<Int>()
            println(plain is LinkedHashSet<*>)
            println(plain as? LinkedHashSet<Int> == null)

            val tags = Tags()
            val inherited: HashSet<Int> = tags
            inherited.add(7)
            println(tags.size)
            println(tags.contains(7))
            val erasedTags: Any = tags
            println(erasedTags is HashSet<*>)

            val hashTags = HashTags()
            hashTags.add(9)
            println(hashTags.size)
            println(hashTags.contains(9))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "LinkedHashSetHierarchy",
            expected: "true\n1\ntrue\ntrue\n1, 2\n2\nfalse\ntrue\n1\ntrue\ntrue\n1\ntrue\n",
            allowDefaultStdlibLibrary: useArtifact
        )
    }
}
