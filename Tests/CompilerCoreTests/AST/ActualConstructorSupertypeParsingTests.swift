#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ActualConstructorSupertypeParsingTests {
    @Test
    func testActualConstructorModifiersAndAnnotationsPreserveSupertypes() throws {
        let (ast, ctx) = try buildASTModule(from: """
        interface IP
        open class Base(message: String)

        actual open class MessageCtor actual constructor(message: String): IP
        actual open class EmptyCtor actual constructor(): IP
        actual open class BaseArgument actual constructor(message: String): Base(message)
        actual open class GenericCtor<T> actual constructor(value: T): IP
        actual open class HiddenCtor @CtorMarker private actual constructor(message: String): IP
        actual open class HeaderCtor(message: String): IP
        actual open class NoSupertype actual constructor(message: String)
        """, includeStdlib: false)

        #expect(!ctx.diagnostics.hasError, "Unexpected parser diagnostics: \(ctx.diagnostics.diagnostics)")

        let messageCtor = try userClassDecl(named: "MessageCtor", in: ast, ctx: ctx)
        #expect(supertypeNames(of: messageCtor, in: ast, ctx: ctx) == ["IP"])

        let emptyCtor = try userClassDecl(named: "EmptyCtor", in: ast, ctx: ctx)
        #expect(supertypeNames(of: emptyCtor, in: ast, ctx: ctx) == ["IP"])

        let baseArgument = try userClassDecl(named: "BaseArgument", in: ast, ctx: ctx)
        #expect(supertypeNames(of: baseArgument, in: ast, ctx: ctx) == ["Base"])
        #expect(baseArgument.superTypeEntries.first?.constructorArgs.count == 1)

        let genericCtor = try userClassDecl(named: "GenericCtor", in: ast, ctx: ctx)
        #expect(genericCtor.typeParams.count == 1)
        #expect(supertypeNames(of: genericCtor, in: ast, ctx: ctx) == ["IP"])

        let hiddenCtor = try userClassDecl(named: "HiddenCtor", in: ast, ctx: ctx)
        #expect(supertypeNames(of: hiddenCtor, in: ast, ctx: ctx) == ["IP"])
        #expect(hiddenCtor.primaryConstructorModifiers.contains(.private))
        #expect(hiddenCtor.primaryConstructorModifiers.contains(.actual))
        #expect(hiddenCtor.primaryConstructorAnnotations.map(\.name) == ["CtorMarker"])

        let headerCtor = try userClassDecl(named: "HeaderCtor", in: ast, ctx: ctx)
        #expect(supertypeNames(of: headerCtor, in: ast, ctx: ctx) == ["IP"])

        let noSupertype = try userClassDecl(named: "NoSupertype", in: ast, ctx: ctx)
        #expect(noSupertype.superTypeEntries.isEmpty)
    }

    @Test
    func testMultilineAnnotatedPrimaryConstructorRetainsParametersAndBody() throws {
        let (ast, ctx) = try buildASTModule(from: """
        class ArrayBox
        @CtorMarker(message = "constructor", nested = ReplaceWith("ArrayBox(size)"))
        @SecondMarker
        public constructor(size: Int) {
            private val storage = size
            val count: Int get() = storage
            operator fun get(index: Int): Int = storage + index
        }
        class GenericBox<T>
        @CtorMarker
        internal constructor(val item: T) : Holder<T> {
            fun read(): T = item
        }
        class MultilineProperties private constructor(
            private val bytes: Int,
            @PublishedApi internal val item: Int = 1,
            public var count: Int = 2,
        ) {
            fun read(): Int = bytes + item + count
        }
        class MultilineGeneric<K, out V> internal constructor(
            @PublishedApi internal val view: Map<K, @UnsafeVariance V>,
        ) : Holder<V> {
            fun read(): Int = 0
        }
        class EmptyAnnotated
        @CtorMarker
        private constructor() {
            fun read(): Int = 0
        }
        class SplitPrefixes private constructor(
            @param:FirstMarker(nested = ReplaceWith("class, fun, val"))
            @SecondMarker
            private
            val
            bytes: Int,
            value: Int,
            private val callback: () -> Int = {
                val inside: Int = 1
                fun nested(): Int = inside
                nested()
            },
            private val selected: Int = choose<Int, Int>(1),
            private val tail: Int = 3,
        ) {
            fun read(): Int = bytes + tail
        }
        """, includeStdlib: false)

        try #require(ctx.diagnostics.diagnostics.isEmpty, "Unexpected parser diagnostics: \(ctx.diagnostics.diagnostics)")
        let box = try userClassDecl(named: "ArrayBox", in: ast, ctx: ctx)
        #expect(box.primaryConstructorParams.map { ctx.interner.resolve($0.name) } == ["size"])
        #expect(box.primaryConstructorModifiers.contains(.public))
        #expect(box.primaryConstructorAnnotations.map(\.name) == ["CtorMarker", "SecondMarker"])
        #expect(box.annotations.isEmpty)
        let boxProperties = try memberProperties(of: box, in: ast)
        #expect(boxProperties.map { ctx.interner.resolve($0.name) } == ["storage", "count"])
        let boxFunctions = try memberFunctions(of: box, in: ast)
        #expect(boxFunctions.map { ctx.interner.resolve($0.name) } == ["get"])
        #expect(boxFunctions.first?.modifiers.contains(.operator) == true)
        #expect(box.hasPrimaryConstructorSyntax)
        let boxRange = box.range
        for function in boxFunctions {
            #expect(boxRange.contains(function.range))
        }

        let generic = try userClassDecl(named: "GenericBox", in: ast, ctx: ctx)
        #expect(generic.typeParams.count == 1)
        #expect(generic.primaryConstructorModifiers.contains(.internal))
        #expect(generic.primaryConstructorParams.map { ctx.interner.resolve($0.name) } == ["item"])
        let genericProperties = try memberProperties(of: generic, in: ast)
        #expect(genericProperties.map { ctx.interner.resolve($0.name) } == ["item"])
        let genericFunctions = try memberFunctions(of: generic, in: ast)
        #expect(genericFunctions.map { ctx.interner.resolve($0.name) } == ["read"])
        #expect(supertypeNames(of: generic, in: ast, ctx: ctx) == ["Holder"])

        let properties = try userClassDecl(named: "MultilineProperties", in: ast, ctx: ctx)
        #expect(properties.primaryConstructorModifiers.contains(.private))
        #expect(properties.primaryConstructorParams.map { ctx.interner.resolve($0.name) } == ["bytes", "item", "count"])
        #expect(properties.primaryConstructorParams.map(\.isProperty) == [true, true, true])
        #expect(properties.primaryConstructorParams.map(\.isMutableProperty) == [false, false, true])
        #expect(properties.primaryConstructorParams.map(\.propertyVisibilityModifiers) == [.some([.private]), .some([.internal]), .some([.public])])
        #expect(properties.primaryConstructorParams[1].annotations.map(\.name) == ["PublishedApi"])
        let propertyMembers = try memberProperties(of: properties, in: ast)
        #expect(propertyMembers.map { ctx.interner.resolve($0.name) } == ["bytes", "item", "count"])
        let propertyFunctions = try memberFunctions(of: properties, in: ast)
        #expect(propertyFunctions.map { ctx.interner.resolve($0.name) } == ["read"])

        let multilineGeneric = try userClassDecl(named: "MultilineGeneric", in: ast, ctx: ctx)
        #expect(multilineGeneric.typeParams.count == 2)
        #expect(multilineGeneric.primaryConstructorModifiers.contains(.internal))
        #expect(multilineGeneric.primaryConstructorParams.map { ctx.interner.resolve($0.name) } == ["view"])
        #expect(multilineGeneric.primaryConstructorParams[0].annotations.map(\.name) == ["PublishedApi"])
        #expect(multilineGeneric.primaryConstructorParams[0].propertyVisibilityModifiers == [.internal])
        #expect(supertypeNames(of: multilineGeneric, in: ast, ctx: ctx) == ["Holder"])
        let genericMembers = try memberProperties(of: multilineGeneric, in: ast)
        #expect(genericMembers.map { ctx.interner.resolve($0.name) } == ["view"])
        let genericMemberFunctions = try memberFunctions(of: multilineGeneric, in: ast)
        #expect(genericMemberFunctions.map { ctx.interner.resolve($0.name) } == ["read"])

        let emptyAnnotated = try userClassDecl(named: "EmptyAnnotated", in: ast, ctx: ctx)
        #expect(emptyAnnotated.hasPrimaryConstructorSyntax)
        #expect(emptyAnnotated.primaryConstructorParams.isEmpty)
        #expect(emptyAnnotated.primaryConstructorModifiers.contains(.private))
        #expect(emptyAnnotated.primaryConstructorAnnotations.map(\.name) == ["CtorMarker"])
        let emptyFunctions = try memberFunctions(of: emptyAnnotated, in: ast)
        #expect(emptyFunctions.map { ctx.interner.resolve($0.name) } == ["read"])

        let split = try userClassDecl(named: "SplitPrefixes", in: ast, ctx: ctx)
        #expect(split.primaryConstructorParams.map { ctx.interner.resolve($0.name) } == ["bytes", "value", "callback", "selected", "tail"])
        #expect(split.primaryConstructorParams[0].annotations.map(\.name) == ["FirstMarker", "SecondMarker"])
        #expect(split.primaryConstructorParams[0].propertyVisibilityModifiers == [.private])
        #expect(split.primaryConstructorParams.map(\.hasDefaultValue) == [false, false, true, true, true])
        let splitProperties = try memberProperties(of: split, in: ast)
        #expect(splitProperties.map { ctx.interner.resolve($0.name) } == ["bytes", "callback", "selected", "tail"])
        let splitFunctions = try memberFunctions(of: split, in: ast)
        #expect(splitFunctions.map { ctx.interner.resolve($0.name) } == ["read"])

        // This is a CST boundary probe. The AST parameter splitter's separate
        // comparison-vs-angle handling is outside this constructor recovery fix.
        let comparisons = parse("""
        class Comparisons private constructor(
            private val threshold: Boolean = left < right,
            private val tail: Int = 3,
        ) { fun read(): Int = tail }
        class Following {}
        fun after(): Int = 1
        """)
        try #require(comparisons.diagnostics.diagnostics.isEmpty)
        #expect(comparisons.arena.nodes.count { $0.kind == .classDecl } == 2)
        #expect(comparisons.arena.nodes.count { $0.kind == .funDecl } == 2)
        #expect(comparisons.arena.nodes.count { $0.kind == .propertyDecl } == 0)

        // A consumed explicit constructor makes the class body the immediate
        // post-header tail. Both class and file ranges must cover its members,
        // or @file:Suppress stops at the constructor and misses header errors.
        let declaration = """
        @Deprecated("old", level = DeprecationLevel.ERROR)
        class Legacy constructor() {
            fun append(data: Legacy): Int = 1
        }
        """
        let suppressed = "@file:Suppress(\"DEPRECATION_ERROR\")\n" + declaration
        let (legacyAST, legacyContext) = try buildASTModule(from: suppressed, includeStdlib: false)
        try #require(legacyContext.diagnostics.diagnostics.isEmpty)
        let legacy = try userClassDecl(named: "Legacy", in: legacyAST, ctx: legacyContext)
        let legacyRange = legacy.range
        let legacyFile = try #require(legacyAST.sortedFiles.first)
        let fileRange = try #require(legacyFile.range)
        #expect(fileRange.end.offset == suppressed.utf8.count)
        #expect(legacyRange.end.offset == suppressed.utf8.count)
        for function in try memberFunctions(of: legacy, in: legacyAST) {
            let functionRange = function.range
            #expect(legacyRange.contains(functionRange))
            #expect(fileRange.contains(functionRange))
        }
        try #require(legacyFile.annotations.contains {
            $0.name == "Suppress" && $0.useSiteTarget == "file"
                && $0.arguments.contains { $0.contains("DEPRECATION_ERROR") }
        })
        try #require(!legacyContext.options.includeStdlib)
        try SemaPhase().run(legacyContext)
        try #require(!legacyContext.diagnostics.hasError,
                     "File suppression did not cover the explicit constructor body: \(legacyContext.diagnostics.diagnostics)")

        let (_, unsuppressedContext) = try buildASTModule(from: declaration, includeStdlib: false)
        try SemaPhase().run(unsuppressedContext)
        let deprecations = unsuppressedContext.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-DEPRECATED" && $0.severity == .error
        }
        try #require(deprecations.count == 1,
                     "The same self-type must retain its error without file suppression: \(unsuppressedContext.diagnostics.diagnostics)")
        #expect(deprecations[0].message.contains("Legacy"))
    }

    @Test
    func testFollowingAnnotatedDeclarationsRemainOutsideConstructorlessClass() throws {
        let (ast, ctx) = try buildASTModule(from: """
        class Empty
        @NextClass("constructor")
        class Following(val value: Int) { fun read(): Int = value }
        class AnotherEmpty
        @NextFunction
        fun unrelated(): Int = 1
        class LastEmpty
        @NextClass("private constructor", nested = ReplaceWith("Following(0)"))
        class AnnotatedFollowing private constructor(
            @PublishedApi internal val item: Int,
        ) {
            fun read(): Int = item
        }
        """, includeStdlib: false)

        try #require(ctx.diagnostics.diagnostics.isEmpty, "Unexpected parser diagnostics: \(ctx.diagnostics.diagnostics)")
        let empty = try userClassDecl(named: "Empty", in: ast, ctx: ctx)
        #expect(empty.primaryConstructorParams.isEmpty)
        #expect(empty.primaryConstructorAnnotations.isEmpty)
        #expect(empty.memberFunctions.isEmpty)
        let following = try userClassDecl(named: "Following", in: ast, ctx: ctx)
        #expect(following.annotations.map(\.name) == ["NextClass"])
        #expect(following.primaryConstructorParams.map { ctx.interner.resolve($0.name) } == ["value"])
        let followingFunctions = try memberFunctions(of: following, in: ast)
        #expect(followingFunctions.map { ctx.interner.resolve($0.name) } == ["read"])
        let another = try userClassDecl(named: "AnotherEmpty", in: ast, ctx: ctx)
        #expect(another.memberFunctions.isEmpty)
        let unrelated = try #require(ast.arena.declarations().compactMap { decl -> FunDecl? in
            guard case let .funDecl(function) = decl,
                  ctx.interner.resolve(function.name) == "unrelated" else { return nil }
            return function
        }.first)
        #expect(unrelated.annotations.map(\.name) == ["NextFunction"])
        let lastEmpty = try userClassDecl(named: "LastEmpty", in: ast, ctx: ctx)
        #expect(!lastEmpty.hasPrimaryConstructorSyntax)
        #expect(lastEmpty.primaryConstructorParams.isEmpty)
        #expect(lastEmpty.primaryConstructorAnnotations.isEmpty)
        #expect(lastEmpty.annotations.isEmpty)
        let annotatedFollowing = try userClassDecl(named: "AnnotatedFollowing", in: ast, ctx: ctx)
        #expect(annotatedFollowing.annotations.map(\.name) == ["NextClass"])
        #expect(annotatedFollowing.primaryConstructorAnnotations.isEmpty)
        #expect(annotatedFollowing.primaryConstructorModifiers.contains(.private))
        #expect(annotatedFollowing.primaryConstructorParams.map { ctx.interner.resolve($0.name) } == ["item"])
        #expect(annotatedFollowing.primaryConstructorParams[0].annotations.map(\.name) == ["PublishedApi"])
        let followingMembers = try memberProperties(of: annotatedFollowing, in: ast)
        #expect(followingMembers.map { ctx.interner.resolve($0.name) } == ["item"])
        let followingMemberFunctions = try memberFunctions(of: annotatedFollowing, in: ast)
        #expect(followingMemberFunctions.map { ctx.interner.resolve($0.name) } == ["read"])

        // Recovery diagnostics belong to separate malformed inputs; valid
        // multiline constructors above must remain completely diagnostic-free.
        let recoveryTails = [
            "class Following {}\nfun after(): Int = 1",
            "@NextClass\nclass Following {}\nfun after(): Int = 1",
            "fun after(): Int = 1\nclass Following {}",
            "object Other {}\nclass Following {}\nfun after(): Int = 1",
            "val outside: Int = 1\nclass Following {}\nfun after(): Int = 1",
            "@NextProperty\nval outside: Int = 1\nclass Following {}\nfun after(): Int = 1",
        ]
        for parameter in ["value: Int", "value: Int = 1", "value: Map<Int, Int>"] {
            for tail in recoveryTails {
                let source = "class Broken private constructor(\n    \(parameter)\n\(tail)"
                let (recoveredAST, recoveredContext) = try buildASTModule(from: source, includeStdlib: false)
                try #require(!recoveredContext.diagnostics.hasError, "Unexpected error diagnostics: \(recoveredContext.diagnostics.diagnostics)")
                let warnings = recoveredContext.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-PARSE-0004" }
                try #require(warnings.count == 1, "Missing constructor recovery warning for \(source)")
                #expect(warnings[0].severity == .warning)
                let recoveredFollowing = try userClassDecl(named: "Following", in: recoveredAST, ctx: recoveredContext)
                #expect(recoveredFollowing.annotations.map(\.name) == (tail.contains("@NextClass") ? ["NextClass"] : []))
                let after = try #require(recoveredAST.arena.declarations().compactMap { decl -> FunDecl? in
                    guard case let .funDecl(function) = decl,
                          recoveredContext.interner.resolve(function.name) == "after" else { return nil }
                    return function
                }.first)
                #expect(after.valueParams.isEmpty)
                if tail.contains("outside") {
                    let outside = recoveredAST.arena.declarations().compactMap { decl -> PropertyDecl? in
                        guard case let .propertyDecl(property) = decl,
                              recoveredContext.interner.resolve(property.name) == "outside" else { return nil }
                        return property
                    }
                    try #require(outside.count == 1)
                    #expect(outside[0].annotations.map(\.name) == (tail.contains("@NextProperty") ? ["NextProperty"] : []))
                }
            }
        }
        let (ordinaryAST, ordinaryContext) = try buildASTModule(from: """
        fun broken(
            value: Int
        class Following {}
        fun after(): Int = 1
        """, includeStdlib: false)
        #expect(ordinaryContext.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0004" })
        _ = try userClassDecl(named: "Following", in: ordinaryAST, ctx: ordinaryContext)
    }

    private func memberProperties(of classDecl: ClassDecl, in ast: ASTModule) throws -> [PropertyDecl] {
        try classDecl.memberProperties.map { declID in
            let property: PropertyDecl? = if case let .propertyDecl(property) = ast.arena.decl(declID) {
                property
            } else {
                nil
            }
            return try #require(property)
        }
    }

    private func memberFunctions(of classDecl: ClassDecl, in ast: ASTModule) throws -> [FunDecl] {
        try classDecl.memberFunctions.map { declID in
            let function: FunDecl? = if case let .funDecl(function) = ast.arena.decl(declID) {
                function
            } else {
                nil
            }
            return try #require(function)
        }
    }

    private func userClassDecl(named name: String, in ast: ASTModule, ctx: CompilationContext) throws -> ClassDecl {
        try #require(ast.arena.declarations().lazy.compactMap { decl -> ClassDecl? in
            guard case let .classDecl(classDecl) = decl,
                  isUserSourceRange(classDecl.range, in: ctx)
            else { return nil }
            return classDecl
        }.first { ctx.interner.resolve($0.name) == name })
    }

    private func supertypeNames(of classDecl: ClassDecl, in ast: ASTModule, ctx: CompilationContext) -> [String] {
        classDecl.superTypeEntries.compactMap { entry in
            guard let typeRef = ast.arena.typeRef(entry.typeRef),
                  case let .named(path, _, _) = typeRef
            else { return nil }
            return path.map { ctx.interner.resolve($0) }.joined(separator: ".")
        }
    }
}
#endif
