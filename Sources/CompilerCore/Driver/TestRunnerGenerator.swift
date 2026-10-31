import Foundation

/// Discovers only declarations in the compilation's user inputs. Wrappers stay
/// in their original lexical scope, so private tests need no visibility changes.
final class TestRunnerGenerator {
    static let entryPoint = "kswiftk.generated.tests.main"
    static let generatedPackage = "kswiftk.generated.tests"
    static let prefix = "__kswiftk_test_"
    private static let annotationNames: Set<String> = ["Test", "Ignore", "BeforeTest", "AfterTest", "BeforeClass", "AfterClass"]
    private static let annotationFQNames = Set(annotationNames.map { "kotlin.test." + $0 })
    private static let lifecycleNames: Set<String> = annotationNames.subtracting(["Ignore"])
    private static let classHookNames: Set<String> = ["BeforeClass", "AfterClass"]

    struct Result {
        let runnerPath: String
        let sources: [String: Data]
    }

    struct Method {
        let id: DeclID
        let declaration: FunDecl
        let symbol: SymbolID
        let tags: Set<String>
        var bridge: String { TestRunnerGenerator.prefix + "bridge_\(id.rawValue)" }
    }

    struct Suite {
        let id: DeclID
        let symbol: SymbolID
        let file: FileID
        let range: SourceRange
        let methods: [DeclID]
        let isObject: Bool
        let isAbstract: Bool
        let isCompanion: Bool
        let companion: DeclID?
        let isGenericOrInner: Bool
    }

    struct Case {
        let name: String
        let wrapper: String
        let file: FileID
        let offset: Int
        let ignored: Bool
        let suiteKey: String
    }

    let context: CompilationContext
    private var suites: [SymbolID: Suite] = [:]
    private var methods: [DeclID: Method] = [:]
    private var insertions: [FileID: [(Int, String)]] = [:]
    private var fileWrappers: [FileID: String] = [:]
    private var cases: [Case] = []
    private var suitePhases: [String: (before: String?, after: String?)] = [:]
    private var bridged: Set<DeclID> = []
    private var sourceTags: [SymbolID: Set<String>] = [:]

    init(context: CompilationContext) { self.context = context }

    func generate() -> Result? {
        guard let ast = context.ast, let sema = context.sema else { return nil }
        let files = Set(context.options.inputs.compactMap { context.sourceManager.fileID(forPath: $0) })
        for symbol in sema.symbols.allSymbols() where symbol.declSite.map({ files.contains($0.start.file) }) == true {
            let name = context.interner.resolve(symbol.name)
            let fqName = qualifiedName(symbol.id)
            if name.hasPrefix(Self.prefix) || fqName == Self.generatedPackage || fqName.hasPrefix(Self.generatedPackage + ".") {
                error("Names beginning with \(Self.prefix) and package \(Self.generatedPackage) are reserved in test mode.", symbol.declSite)
            }
        }
        for file in ast.sortedFiles where files.contains(file.fileID) {
            collect(file.topLevelDecls, file: file.fileID)
            let topLevel = file.topLevelDecls.compactMap { methods[$0] }
            let before = topLevel.filter { $0.tags.contains("BeforeTest") }
            let after = topLevel.filter { $0.tags.contains("AfterTest") }
            let tests = topLevel.filter { $0.tags.contains("Test") }
            if tests.contains(where: { !$0.tags.contains("Ignore") }) {
                addSuitePhases(topLevel, suite: nil, file: file.fileID)
            }
            for test in tests {
                let fileName = URL(fileURLWithPath: context.sourceManager.path(of: file.fileID)).lastPathComponent
                let name = qualifiedName(test.symbol) + " [" + fileName + "]"
                addCase(test, suite: nil, before: before, after: after, name: name,
                        ignored: test.tags.contains("Ignore"), file: file.fileID)
            }
        }
        for suite in suites.values.sorted(by: { qualifiedName($0.symbol) < qualifiedName($1.symbol) }) where !suite.isAbstract && !suite.isCompanion {
            let inherited = inheritedMethods(suite, visited: [])
            let tests = inherited.filter { $0.tags.contains("Test") }
            guard !tests.isEmpty else { continue }
            let before = inherited.filter { $0.tags.contains("BeforeTest") }
            let after = inherited.filter { $0.tags.contains("AfterTest") }
            let suiteIgnored = tags(suite.symbol).contains("Ignore")
            if tests.contains(where: { !suiteIgnored && !$0.tags.contains("Ignore") }) {
                validateSuite(suite)
                let hookOwner = suite.isObject ? suite : suite.companion.flatMap { companion in
                    suites.values.first { $0.id == companion }
                }
                if let hookOwner {
                    addSuitePhases(inheritedMethods(hookOwner, visited: []), suite: hookOwner,
                                   file: suite.file, suiteKey: key(suite: suite, file: suite.file))
                }
            }
            for test in tests {
                addCase(test, suite: suite, before: before, after: after,
                        name: qualifiedName(suite.symbol) + "." + context.interner.resolve(test.declaration.name),
                        ignored: suiteIgnored || test.tags.contains("Ignore"), file: suite.file)
            }
        }
        guard !context.diagnostics.hasError else { return nil }
        cases.sort {
            if $0.name != $1.name { return $0.name < $1.name }
            let lhs = context.sourceManager.path(of: $0.file)
            let rhs = context.sourceManager.path(of: $1.file)
            return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
        }
        var sources: [String: Data] = [:]
        for path in context.options.inputs {
            guard let file = context.sourceManager.fileID(forPath: path) else { continue }
            var data = context.sourceManager.contents(of: file)
            for (offset, text) in (insertions[file] ?? []).sorted(by: { $0.0 > $1.0 }) {
                data.insert(contentsOf: text.utf8, at: offset)
            }
            data.append(contentsOf: (fileWrappers[file] ?? "").utf8)
            sources[path] = data
        }
        let directory = URL(fileURLWithPath: context.options.inputs.first ?? context.options.outputPath).deletingLastPathComponent()
        let runnerPath = directory.appendingPathComponent(Self.prefix + "runner.kt").path
        guard !context.options.inputs.contains(runnerPath), !FileManager.default.fileExists(atPath: runnerPath) else {
            error("Generated test runner path collides with an input file: \(runnerPath)", nil)
            return nil
        }
        sources[runnerPath] = Data(renderRunner().utf8)
        return Result(runnerPath: runnerPath, sources: sources)
    }

    private func collect(_ declarations: [DeclID], file: FileID) {
        guard let ast = context.ast, let sema = context.sema else { return }
        let sourceFile = ast.file(for: file)
        for id in declarations {
            guard let declaration = ast.arena.decl(id), let symbol = sema.bindings.declSymbol(for: id) else { continue }
            // Resolve against the complete table and the declaration's lexical
            // scope, without the legacy unscoped annotation fallback.
            if let sourceFile {
                sourceTags[symbol] = Set(declaration.annotations.compactMap { annotation in
                    if annotation.name.contains("."), !Self.annotationFQNames.contains(annotation.name) {
                        return nil
                    }
                    guard let resolved = resolveAnnotationSymbol(named: annotation.name, in: sourceFile,
                                                                 symbols: sema.symbols, interner: context.interner,
                                                                 enclosingSymbol: sema.symbols.parentSymbol(for: symbol),
                                                                 allowGlobalShortNameFallback: false),
                          let fqName = sema.symbols.symbol(resolved)?.fqName.map(context.interner.resolve).joined(separator: "."),
                          fqName.hasPrefix("kotlin.test.") else { return nil }
                    let shortName = String(fqName.dropFirst("kotlin.test.".count))
                    return Self.annotationNames.contains(shortName) ? shortName : nil
                })
            }
            switch declaration {
            case let .funDecl(function):
                let annotations = tags(symbol)
                if !annotations.isDisjoint(with: Self.lifecycleNames) {
                    validateMethod(function, symbol: symbol)
                }
                methods[id] = Method(id: id, declaration: function, symbol: symbol, tags: annotations)
            case let .classDecl(klass):
                suites[symbol] = Suite(id: id, symbol: symbol, file: file, range: klass.range,
                                       methods: klass.memberFunctions, isObject: false,
                                       isAbstract: klass.modifiers.contains(.abstract) || klass.modifiers.contains(.sealed),
                                       isCompanion: false, companion: klass.companionObject,
                                       isGenericOrInner: !klass.typeParams.isEmpty || klass.isInner)
                collect(klass.memberFunctions + klass.nestedClasses + klass.nestedObjects + (klass.companionObject.map { [$0] } ?? []), file: file)
                for id in klass.memberFunctions {
                    guard let function = ast.arena.decl(id), case let .funDecl(method) = function,
                          let methodSymbol = sema.bindings.declSymbol(for: id) else { continue }
                    // Native warns and does not register class hooks on instances.
                    for name in tags(methodSymbol).intersection(Self.classHookNames).sorted() {
                        context.diagnostics.warning("KSWIFTK-TEST-0002",
                            "Annotation kotlin.test.\(name) is only allowed for methods of an object (named or companion) or top level functions.",
                            range: method.range)
                    }
                }
            case let .objectDecl(object):
                suites[symbol] = Suite(id: id, symbol: symbol, file: file, range: object.range,
                                       methods: object.memberFunctions, isObject: true, isAbstract: false,
                                       isCompanion: object.modifiers.contains(.companion), companion: nil, isGenericOrInner: false)
                collect(object.memberFunctions + object.nestedClasses + object.nestedObjects, file: file)
            case let .interfaceDecl(interface):
                collect(interface.nestedClasses + interface.nestedObjects + (interface.companionObject.map { [$0] } ?? []), file: file)
            default:
                break // Interfaces do not contribute Native test annotations.
            }
        }
    }

    private func tags(_ symbol: SymbolID) -> Set<String> {
        if let source = sourceTags[symbol] { return source }
        guard let sema = context.sema else { return [] }
        return Set(sema.symbols.annotations(for: symbol).compactMap {
            guard $0.annotationFQName.hasPrefix("kotlin.test.") else { return nil }
            let name = String($0.annotationFQName.dropFirst("kotlin.test.".count))
            return Self.annotationNames.contains(name) ? name : nil
        })
    }

    private func validateMethod(_ function: FunDecl, symbol: SymbolID) {
        guard let sema = context.sema else { return }
        if !function.valueParams.isEmpty || function.receiverType != nil || !function.contextReceivers.isEmpty
            || !function.typeParams.isEmpty || function.isSuspend
            || sema.symbols.functionSignature(for: symbol)?.returnType != sema.types.unitType {
            error("A test or lifecycle hook must be a non-suspend, non-generic Unit function without parameters or extension/context receivers.", function.range)
        }
    }

    /// A base bridge dispatches the original member normally, including an
    /// override without annotations. Private base hooks remain callable only
    /// through their own scope. Overloads with arguments do not hide a test.
    private func inheritedMethods(_ suite: Suite, visited: Set<SymbolID>) -> [Method] {
        guard let sema = context.sema, !visited.contains(suite.symbol) else { return [] }
        var next = visited
        next.insert(suite.symbol)
        var result: [Method] = []
        for parent in sema.symbols.directSupertypes(for: suite.symbol) {
            if let parentSuite = suites[parent] { result += inheritedMethods(parentSuite, visited: next) }
        }
        for id in suite.methods {
            guard let method = methods[id] else { continue }
            let overridden = result.filter {
                $0.declaration.name == method.declaration.name && !$0.declaration.modifiers.contains(.private)
                    && method.declaration.modifiers.contains(.override) && method.declaration.valueParams.isEmpty
                    && method.declaration.receiverType == nil && method.declaration.contextReceivers.isEmpty
            }
            var annotations = overridden.reduce(method.tags) { $0.union($1.tags) }
            // Native takes Ignore from the nearest declaration carrying Test.
            // An explicit Test replaces the inherited flag; Ignore alone on an
            // override does not change the inherited test's ignored status.
            let testTags = method.tags.contains("Test") ? method.tags
                : overridden.first(where: { $0.tags.contains("Test") })?.tags
            if let testTags {
                if testTags.contains("Ignore") { annotations.insert("Ignore") }
                else { annotations.remove("Ignore") }
            }
            guard !annotations.isDisjoint(with: Self.lifecycleNames) else { continue }
            result.removeAll { candidate in overridden.contains { $0.id == candidate.id } }
            validateMethod(method.declaration, symbol: method.symbol)
            result.append(Method(id: method.id, declaration: method.declaration, symbol: method.symbol, tags: annotations))
        }
        return result
    }

    private func validateSuite(_ suite: Suite) {
        guard let sema = context.sema, let symbol = sema.symbols.symbol(suite.symbol) else { return }
        let visibility = VisibilityChecker(symbols: sema.symbols, sourceManager: context.sourceManager, interner: context.interner)
        var owner: SymbolID? = suite.symbol
        var accessible = true
        while let current = owner, let info = sema.symbols.symbol(current), info.kind != .package {
            accessible = accessible && visibility.isAccessible(info, fromFile: suite.file, enclosingClass: nil)
            owner = sema.symbols.parentSymbol(for: current)
        }
        if !accessible || suite.isGenericOrInner {
            error("A test suite must be accessible from its file and must not be generic or inner.", suite.range)
        }
        guard !suite.isObject else { return }
        let constructors = sema.symbols.children(ofFQName: symbol.fqName).compactMap { sema.symbols.symbol($0) }.filter { $0.kind == .constructor }
        let usable = constructors.contains { constructor in
            guard visibility.isAccessible(constructor, fromFile: suite.file, enclosingClass: nil),
                  let signature = sema.symbols.functionSignature(for: constructor.id) else { return false }
            return signature.parameterTypes.indices.allSatisfy { index in
                (index < signature.valueParameterHasDefaultValues.count && signature.valueParameterHasDefaultValues[index])
                    || (index < signature.valueParameterIsVararg.count && signature.valueParameterIsVararg[index])
            }
        }
        if !usable { error("A test class requires an accessible constructor callable without arguments.", suite.range) }
    }

    private func addCase(_ test: Method, suite: Suite?, before: [Method], after: [Method], name: String, ignored: Bool, file: FileID) {
        let suffix = "\(suite?.id.rawValue ?? -1)_\(test.id.rawValue)".replacingOccurrences(of: "-", with: "n")
        let wrapper = Self.prefix + "case_" + suffix
        let package = context.ast?.file(for: file)?.packageFQName.map(context.interner.resolve).map(identifier).joined(separator: ".") ?? ""
        cases.append(Case(name: name, wrapper: package.isEmpty ? wrapper : package + "." + wrapper,
                          file: file, offset: test.declaration.range.start.offset, ignored: ignored,
                          suiteKey: key(suite: suite, file: file)))
        if ignored { return }
        let body: String
        if let suite {
            for method in before + [test] + after { addBridge(method) }
            let member = Self.prefix + "run_" + suffix
            insert("\nfun \(member)(): Unit {\n" + lifecycle(test.bridge + "()", before: before.map { $0.bridge + "()" }, after: after.map { $0.bridge + "()" }, name: name) + "\n}\n", into: suite)
            body = "val __kswiftk_test_instance = \(receiver(suite))\n__kswiftk_test_instance.\(member)()"
        } else {
            body = lifecycle(identifier(context.interner.resolve(test.declaration.name)) + "()",
                             before: before.map { identifier(context.interner.resolve($0.declaration.name)) + "()" },
                             after: after.map { identifier(context.interner.resolve($0.declaration.name)) + "()" }, name: name)
        }
        fileWrappers[file, default: ""] += """


        fun \(wrapper)(__kswiftk_test_reporter: \(Self.generatedPackage).Reporter): Unit {
            try {
                \(body)
                __kswiftk_test_reporter.pass(\(literal(name)))
            } catch (__kswiftk_test_failure: kotlin.Throwable) {
                __kswiftk_test_reporter.fail(\(literal(name)), __kswiftk_test_failure)
            }
        }

        """
    }

    private func key(suite: Suite?, file: FileID) -> String {
        suite.map { "suite_\($0.id.rawValue)" } ?? "file_\(file.rawValue)"
    }

    private func receiver(_ suite: Suite, instantiate: Bool = true) -> String {
        let filePackage = context.ast?.file(for: suite.file)?.packageFQName ?? []
        let components = context.sema?.symbols.symbol(suite.symbol)?.fqName ?? []
        return components.dropFirst(filePackage.count).map { identifier(context.interner.resolve($0)) }.joined(separator: ".")
            + (suite.isObject || !instantiate ? "" : "()")
    }

    private func addSuitePhases(_ hooks: [Method], suite: Suite?, file: FileID, suiteKey: String? = nil) {
        let group = suiteKey ?? key(suite: suite, file: file)
        let visibility = context.sema.map { VisibilityChecker(symbols: $0.symbols, sourceManager: context.sourceManager, interner: context.interner) }
        var lexicalOwner: Suite?
        if let suite, suite.isCompanion, let sema = context.sema,
           let symbol = sema.symbols.symbol(suite.symbol),
           visibility?.isAccessible(symbol, fromFile: file, enclosingClass: nil) == false,
           let parent = sema.symbols.parentSymbol(for: suite.symbol) {
            lexicalOwner = suites[parent]
        }
        let accessObject = Self.prefix + "suite_hooks_" + group
        var accessMethods = ""
        // Native registers declared hooks before fake overrides, which it sorts by name.
        let own = hooks.filter { context.sema?.symbols.parentSymbol(for: $0.symbol) == suite?.symbol }
        let inherited = hooks.filter { context.sema?.symbols.parentSymbol(for: $0.symbol) != suite?.symbol && !$0.declaration.modifiers.contains(.private) }
            .sorted { context.interner.resolve($0.declaration.name) < context.interner.resolve($1.declaration.name) }
        let ordered = suite == nil ? hooks : own + inherited
        func phase(_ tag: String) -> String? {
            let selected = ordered.filter { $0.tags.contains(tag) }
            guard !selected.isEmpty else { return nil }
            let wrapper = Self.prefix + tag + "_" + group
            var calls = selected.map { method in
                if let suite {
                    addBridge(method)
                    let target = lexicalOwner.map { receiver($0, instantiate: false) } ?? receiver(suite)
                    return target + "." + method.bridge + "()"
                }
                return identifier(context.interner.resolve(method.declaration.name)) + "()"
            }.joined(separator: "\n")
            if let lexicalOwner {
                // Keep hidden companions accessible from their original class
                // scope without constructing a test instance or changing visibility.
                let member = tag == "BeforeClass" ? "before" : "after"
                accessMethods += "\nfun \(member)(): Unit {\n\(calls)\n}\n"
                calls = receiver(lexicalOwner, instantiate: false) + "." + accessObject + "." + member + "()"
            }
            fileWrappers[file, default: ""] += "\nfun \(wrapper)(): Unit {\n\(calls)\n}\n"
            let package = context.ast?.file(for: file)?.packageFQName.map(context.interner.resolve).map(identifier).joined(separator: ".") ?? ""
            return package.isEmpty ? wrapper : package + "." + wrapper
        }
        suitePhases[group] = (phase("BeforeClass"), phase("AfterClass"))
        if let lexicalOwner, !accessMethods.isEmpty {
            insert("\nobject \(accessObject) {\n\(accessMethods)\n}\n", into: lexicalOwner)
        }
    }

    private func addBridge(_ method: Method) {
        guard bridged.insert(method.id).inserted, let sema = context.sema,
              let parent = sema.symbols.parentSymbol(for: method.symbol), let suite = suites[parent] else { return }
        insert("\nfun \(method.bridge)(): Unit { \(identifier(context.interner.resolve(method.declaration.name)))() }\n", into: suite)
    }

    private func insert(_ text: String, into suite: Suite) {
        let tokens = context.tokensByFile.first(where: { $0.0 == suite.file })?.1 ?? []
        var lastIndex = tokens.lastIndex { $0.range.start.offset >= suite.range.start.offset && $0.range.end.offset <= suite.range.end.offset && $0.kind != .eof }
        while let index = lastIndex, tokens[index].kind == .symbol(.semicolon) {
            lastIndex = index > 0 ? index - 1 : nil
        }
        var closingOffset: Int?
        if let lastIndex {
            if tokens[lastIndex].kind == .symbol(.rBrace) {
                closingOffset = tokens[lastIndex].range.start.offset
            } else if lastIndex + 1 < tokens.count, tokens[lastIndex + 1].kind == .symbol(.lBrace) {
                // Bare nominal declarations can have a header-only AST range.
                // Walk the actual body tokens rather than appending a new body.
                var depth = 0
                for token in tokens[(lastIndex + 1)...] {
                    if token.kind == .symbol(.lBrace) { depth += 1 }
                    if token.kind == .symbol(.rBrace) {
                        depth -= 1
                        if depth == 0 { closingOffset = token.range.start.offset; break }
                    }
                }
            }
        }
        if let closingOffset {
            insertions[suite.file, default: []].append((closingOffset, text))
        } else {
            // A declaration with inherited tests may have no body of its own.
            let offset = lastIndex.map { tokens[$0].range.end.offset } ?? suite.range.end.offset
            if let index = insertions[suite.file]?.firstIndex(where: { $0.0 == offset }) {
                let old = insertions[suite.file]![index].1
                insertions[suite.file]![index].1 = String(old.dropLast(2)) + text + "}\n"
            } else {
                insertions[suite.file, default: []].append((offset, " {\n" + text + "}\n"))
            }
        }
    }

    private func lifecycle(_ test: String, before: [String], after: [String], name: String) -> String {
        var body = "var __kswiftk_test_primary: kotlin.Throwable? = null\ntry {\n" + (before + [test]).joined(separator: "\n")
        body += "\n} catch (__kswiftk_test_failure: kotlin.Throwable) { __kswiftk_test_primary = __kswiftk_test_failure }\n"
        // Reverse order unwinds setup. Every cleanup is attempted, even after
        // another cleanup fails; preserve the original failure as the primary.
        for hook in after.reversed() {
            body += "try { \(hook) } catch (__kswiftk_test_failure: kotlin.Throwable) {\nif (__kswiftk_test_primary == null) { __kswiftk_test_primary = __kswiftk_test_failure } else { kotlin.io.println(\(literal("AFTER " + name + ": ")) + __kswiftk_test_failure.message) }\n}\n"
        }
        return body + "if (__kswiftk_test_primary != null) { throw __kswiftk_test_primary!! }"
    }

    private func renderRunner() -> String {
        var groups: [String] = []
        var grouped: [String: [Case]] = [:]
        for test in cases {
            if grouped[test.suiteKey] == nil { groups.append(test.suiteKey) }
            grouped[test.suiteKey, default: []].append(test)
        }
        let calls = groups.flatMap { group -> [String] in
            let tests = grouped[group] ?? []
            let phases = suitePhases[group]
            var calls: [String] = []
            if let before = phases?.before { calls.append(before + "()") }
            calls += tests.map { $0.ignored ? "reporter.skip(\(literal($0.name)))" : "\($0.wrapper)(reporter)" }
            if let after = phases?.after { calls.append(after + "()") }
            return calls
        }.joined(separator: "\n")
        let wrappers = cases.filter { !$0.ignored }.map(\.wrapper)
            + groups.flatMap { [suitePhases[$0]?.before, suitePhases[$0]?.after].compactMap { $0 } }
        let imports = wrappers.filter { !$0.contains(".") }.map { "import " + $0 }.joined(separator: "\n")
        return """
        package \(Self.generatedPackage)
        \(imports)

        class Reporter {
            var passed: Int = 0
            var failed: Int = 0
            var skipped: Int = 0
            fun pass(name: String): Unit { passed += 1; println("PASS " + name) }
            fun fail(name: String, failure: kotlin.Throwable): Unit { failed += 1; println("FAIL " + name + ": " + failure.message) }
            fun skip(name: String): Unit { skipped += 1; println("SKIP " + name) }
            fun finish(): Unit {
                println("Tests: " + passed + " passed, " + failed + " failed, " + skipped + " skipped")
                if (failed != 0) { kotlin.system.exitProcess(1) }
            }
        }
        fun main(): Unit {
            val reporter = Reporter()
            \(calls)
            reporter.finish()
        }

        """
    }

    private func qualifiedName(_ symbol: SymbolID, quoted: Bool = false) -> String {
        let components = context.sema?.symbols.symbol(symbol)?.fqName.map(context.interner.resolve) ?? []
        return components.map { quoted ? identifier($0) : $0 }.joined(separator: ".")
    }

    private func identifier(_ name: String) -> String { "`" + name + "`" }

    private func literal(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t") + "\""
    }

    private func error(_ message: String, _ range: SourceRange?) {
        context.diagnostics.error("KSWIFTK-TEST-0001", message, range: range)
    }
}
