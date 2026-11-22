#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func kotlinClasspathClassBoundsKeepMetadataNullability() throws {
        try withWorkspace { root in
            try """
            package dep

            class KBox<T : Number>(val value: T) {
                fun get(): T = value
            }
            """.write(to: root.appendingPathComponent("KBox.kt"), atomically: true, encoding: .utf8)
            let kotlinLibrary = root.appendingPathComponent("kbox.jar")
            let compiled = try jvmTool("kotlinc", ["KBox.kt", "-d", kotlinLibrary.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")

            let valid = try m22Build(
                root: root,
                sources: [("Valid.kt", """
                import dep.KBox

                fun valid(): KBox<Int> = KBox(1)
                """)],
                name: "valid.jar",
                classpath: [kotlinLibrary.path]
            )
            try #require(valid.1 == 0, "\(valid.2.map(\.message))")

            let invalid = try m22Build(
                root: root,
                sources: [("Invalid.kt", """
                import dep.KBox

                fun invalid(): KBox<Int?> = KBox<Int?>(null)
                """)],
                name: "invalid.jar",
                classpath: [kotlinLibrary.path]
            )
            #expect(invalid.1 != 0)
            #expect(invalid.2.contains { $0.severity == .error && $0.code == "KSWIFTK-SEMA-BOUND" })

            try """
            package dep;
            public class JBox<T extends Number> {
                private T value;
                public JBox(T value) { this.value = value; }
                public T get() { return value; }
            }
            """.write(to: root.appendingPathComponent("JBox.java"), atomically: true, encoding: .utf8)
            try FileManager.default.createDirectory(at: root.appendingPathComponent("java-classes"), withIntermediateDirectories: true)
            let javac = try jvmTool("javac", ["--release", "8", "-d", "java-classes", "JBox.java"], root: root)
            try #require(javac.exitCode == 0, "\(javac.stderr)")
            let javaLibrary = root.appendingPathComponent("jbox.jar")
            let jar = try jvmTool("jar", ["cf", javaLibrary.path, "-C", "java-classes", "."], root: root)
            try #require(jar.exitCode == 0, "\(jar.stderr)")

            let javaConsumer = try m22Build(
                root: root,
                sources: [("JavaConsumer.kt", """
                import dep.JBox

                fun valid(): JBox<Int> = JBox(1)
                fun nullable(): JBox<Int?> = JBox(null)
                """)],
                name: "java-consumer.jar",
                classpath: [javaLibrary.path]
            )
            try #require(javaConsumer.1 == 0, "\(javaConsumer.2.map(\.message))")
        }
    }

    @Test
    func kotlinClasspathBoundsPreserveDependencyShapes() throws {
        try withWorkspace { root in
            try """
            package dep

            class DateBox<T : java.util.Date>

            open class Key<T>
            class StringKey : Key<String>()
            class Registry<T : Key<String>>

            class Marker<T>
            class Outer<A> {
                inner class Box<T : Marker<A>>
            }
            """.write(to: root.appendingPathComponent("Bounds.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("bounds.jar")
            let compiled = try jvmTool("kotlinc", ["Bounds.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")

            let dateBox = try m22Build(
                root: root,
                sources: [("DateBoxConsumer.kt", """
                import dep.DateBox

                fun use(box: DateBox<*>?) {}
                """)],
                name: "datebox.jar",
                classpath: [library.path]
            )
            try #require(dateBox.1 == 0, "\(dateBox.2.map(\.message))")

            let registry = try m22Build(
                root: root,
                sources: [("RegistryConsumer.kt", """
                import dep.Registry
                import dep.StringKey

                fun use(): Registry<StringKey>? = null
                """)],
                name: "registry.jar",
                classpath: [library.path]
            )
            try #require(registry.1 == 0, "\(registry.2.map(\.message))")

            let registryInvalid = try m22Build(
                root: root,
                sources: [("RegistryInvalid.kt", """
                import dep.Registry

                fun bad(): Registry<String>? = null
                """)],
                name: "registry-invalid.jar",
                classpath: [library.path]
            )
            #expect(registryInvalid.1 != 0)
            #expect(registryInvalid.2.contains { $0.severity == .error && $0.code == "KSWIFTK-SEMA-BOUND" })

            let inner = try m22Build(
                root: root,
                sources: [("InnerConsumer.kt", """
                import dep.Marker
                import dep.Outer

                fun use(box: Outer<String>.Box<Marker<String>>?) {}
                """)],
                name: "inner.jar",
                classpath: [library.path]
            )
            try #require(inner.1 == 0, "\(inner.2.map(\.message))")

            let innerInvalid = try m22Build(
                root: root,
                sources: [("InnerInvalid.kt", """
                import dep.Marker
                import dep.Outer

                fun bad(box: Outer<String>.Box<Marker<Int>>?) {}
                """)],
                name: "inner-invalid.jar",
                classpath: [library.path]
            )
            #expect(innerInvalid.1 != 0)
            #expect(innerInvalid.2.contains { $0.severity == .error && $0.code == "KSWIFTK-SEMA-BOUND" })
        }
    }

    @Test
    func kotlinClasspathBoundsValidateInnerOuterAndKeywordShapes() throws {
        try withWorkspace { root in
            try """
            package dep

            class Marker<T>
            class Outer<A> {
                inner class Box<T : Marker<A>>
                fun use(box: Box<Marker<A>>?) {}
            }
            class BoundedOuter<A : Number> {
                inner class Item
            }
            class `when`
            open class KeywordParent<T>
            open class KeywordChild : KeywordParent<`when`>()
            """.write(to: root.appendingPathComponent("ReviewBounds.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("review-bounds.jar")
            let compiled = try jvmTool("kotlinc", ["ReviewBounds.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")

            let innerScope = try m22Build(
                root: root,
                sources: [("InnerScopeConsumer.kt", """
                import dep.Outer

                fun callUse(outer: Outer<String>) { outer.use(null) }
                """)],
                name: "inner-scope.jar",
                classpath: [library.path]
            )
            try #require(innerScope.1 == 0, "\(innerScope.2.map(\.message))")

            let boundedValid = try m22Build(
                root: root,
                sources: [("BoundedOuterValid.kt", """
                import dep.BoundedOuter

                fun ok(item: BoundedOuter<Int>.Item?) {}
                """)],
                name: "bounded-outer-valid.jar",
                classpath: [library.path]
            )
            try #require(boundedValid.1 == 0, "\(boundedValid.2.map(\.message))")

            let boundedInvalid = try m22Build(
                root: root,
                sources: [("BoundedOuterInvalid.kt", """
                import dep.BoundedOuter

                fun ok(item: BoundedOuter<Int>.Item?) {}
                fun bad(item: BoundedOuter<String>.Item?) {}
                """)],
                name: "bounded-outer-invalid.jar",
                classpath: [library.path]
            )
            #expect(boundedInvalid.1 != 0)
            #expect(boundedInvalid.2.contains { $0.severity == .error && $0.code == "KSWIFTK-SEMA-BOUND" })

            let keyword = try m22Build(
                root: root,
                sources: [("KeywordConsumer.kt", """
                import dep.KeywordChild

                open class Mine : KeywordChild()

                fun use(value: Mine) {}
                """)],
                name: "keyword.jar",
                classpath: [library.path]
            )
            try #require(keyword.1 == 0, "\(keyword.2.map(\.message))")
        }
    }

    @Test
    func kotlinClasspathKeywordMetadataRemainsMatchable() throws {
        try withWorkspace { root in
            try """
            package dep

            @JvmInline value class `data`(val value: Int)
            class Service { fun take(value: `data`) {} }

            abstract class Parent<`data`> { abstract val value: dep.`data` }
            class Child : Parent<String>() { override val value: dep.`data` get() = TODO() }

            @JvmInline value class `when`(val value: Int)
            class Holder(val value: `when`)
            """.write(to: root.appendingPathComponent("KeywordMetadata.kt"), atomically: true, encoding: .utf8)
            let library = root.appendingPathComponent("keyword-metadata.jar")
            let compiled = try jvmTool("kotlinc", ["KeywordMetadata.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")

            let method = try m22Build(
                root: root,
                sources: [("DataMethodConsumer.kt", """
                package dep

                fun take(service: Service) { service.take(`data`(1)) }
                """)],
                name: "data-method.jar",
                classpath: [library.path]
            )
            try #require(method.1 == 0, "\(method.2.map(\.message))")

            let property = try m22Build(
                root: root,
                sources: [("DataPropertyConsumer.kt", """
                package dep

                fun prop(child: Child): `data` = child.value
                """)],
                name: "data-property.jar",
                classpath: [library.path]
            )
            try #require(property.1 == 0, "\(property.2.map(\.message))")

            let constructor = try m22Build(
                root: root,
                sources: [("WhenConsumer.kt", """
                package dep

                fun make(): Holder = Holder(`when`(1))
                """)],
                name: "when-constructor.jar",
                classpath: [library.path]
            )
            try #require(constructor.1 == 0, "\(constructor.2.map(\.message))")
        }
    }

    @Test
    func kotlinKeywordEscapedTypeEscapesUnqualifiedKeywords() throws {
        let index = try JVMClasspathIndex.load([])
        #expect(index.kotlinKeywordEscapedType("Parent<when>") == "Parent<`when`>")
        #expect(index.kotlinKeywordEscapedType("Parent<when?>") == "Parent<`when`?>")
        #expect(index.kotlinKeywordEscapedType("Parent<in dep.Foo, out dep.Bar>") == "Parent<in dep.Foo, out dep.Bar>")
        #expect(index.kotlinKeywordEscapedType("suspend (dep.when) -> dep.when") == "suspend (dep.`when`) -> dep.`when`")
    }
}
#endif
