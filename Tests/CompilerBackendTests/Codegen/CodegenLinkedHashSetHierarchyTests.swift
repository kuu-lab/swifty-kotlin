@testable import CompilerCore
import Testing
import TestStdlibCache

@Suite
struct CodegenLinkedHashSetHierarchyTests {
    @Test(arguments: [false, true])
    func setSizeAndContainsOverridesDispatchThroughStaticSupertypes(useArtifact: Bool) throws {
        let source = """
        class CustomSet : LinkedHashSet<Int>() {
            override val size: Int
                get() = 42
            override fun contains(element: Int): Boolean = true
        }
        class PlainHashSet : HashSet<Int>()

        fun probeLinked(value: LinkedHashSet<Int>) {
            println(value.size)
            println(value.contains(999))
        }
        fun probeHash(value: HashSet<Int>) {
            println(value.size)
            println(value.contains(999))
        }
        fun probeMutable(value: MutableSet<Int>) {
            println(value.size)
            println(value.contains(999))
        }

        fun main() {
            val custom = CustomSet()
            probeLinked(custom)
            probeHash(custom)
            probeMutable(custom)

            val plainHash = PlainHashSet()
            plainHash.add(1)
            probeHash(plainHash)

            val linked: LinkedHashSet<Int> = LinkedHashSet()
            linked.add(1)
            println(linked.size)
            println(linked.contains(1))

            val hash: HashSet<Int> = HashSet()
            hash.add(1)
            println(hash.size)
            println(hash.contains(1))

            val mutable: MutableSet<Int> = mutableSetOf(1)
            println(mutable.size)
            println(mutable.contains(1))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "LinkedHashSetOverrideDispatch",
            expected: "42\ntrue\n42\ntrue\n42\ntrue\n1\nfalse\n1\ntrue\n1\ntrue\n1\ntrue\n",
            allowDefaultStdlibLibrary: useArtifact
        )
    }

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
