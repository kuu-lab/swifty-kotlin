@testable import CompilerCore
import Foundation
import Testing

@Suite(.serialized)
struct ReflectFindAnnotationImportTests {
    @Test(arguments: [true, false])
    func originalCases(useArtifact: Bool) throws {
        if useArtifact { _ = try testStdlibArtifactPath() }
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 4 { root.deleteLastPathComponent() }
        for (name, expected) in [
            ("annotation_reflection", "annotation count: 2\nfound MyAnnotation\nfound AnotherAnnotation\nunannotated count: 0\n"),
            ("metadata_api", "User\ntrue\n1\n1\ntrue\n"),
        ] {
            let source = try String(contentsOf: root.appendingPathComponent(
                "Scripts/diff_cases/\(name).kt"
            ), encoding: .utf8)
            try assertKotlinOutput(source, moduleName: "FindAnnotation_\(name)", expected: expected,
                                  allowDefaultStdlibLibrary: useArtifact)
        }
    }

    @Test(arguments: [true, false])
    func aliasAndAnnotatedElement(useArtifact: Bool) throws {
        if useArtifact { _ = try testStdlibArtifactPath() }
        try assertKotlinOutput("""
        import kotlin.reflect.KAnnotatedElement
        import kotlin.reflect.KClass
        import kotlin.reflect.full.findAnnotation as lookup
        annotation class Tag(val value: String)
        annotation class Absent
        @Tag("native") class Host
        class Plain
        class Element(override val annotations: List<Annotation>) : KAnnotatedElement
        fun read(k: KClass<*>): Tag? = k.lookup<Tag>()
        fun inferred(k: KClass<*>): Tag? = k.lookup()
        fun main() {
            val present: Tag? = Host::class.lookup<Tag>()
            println(present != null)
            println(read(Host::class) != null)
            println(inferred(Host::class) != null)
            println(Host::class.lookup<Absent>() == null)
            println(Plain::class.lookup<Tag>() == null)
            val element: KAnnotatedElement = Element(listOf(Tag("source")))
            println(element.lookup<Tag>()?.value)
            println(element.lookup<Absent>() == null)
            val empty: KAnnotatedElement = Element(emptyList())
            println(empty.lookup<Tag>() == null)
            val native: KAnnotatedElement = Host::class
            println(native.annotations.size)
        }
        """, moduleName: "FindAnnotationAlias", expected: "true\ntrue\ntrue\ntrue\ntrue\nsource\ntrue\ntrue\n1\n",
            allowDefaultStdlibLibrary: useArtifact)
    }
}
