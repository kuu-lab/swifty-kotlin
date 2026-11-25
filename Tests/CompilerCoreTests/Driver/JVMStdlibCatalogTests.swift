#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

struct JVMStdlibCatalogTests {
    @Test
    func declarationsArePackagedSeparatelyFromCompiledBodies() throws {
        let manifest = try JVMStdlibCatalog.manifest()
        #expect(manifest.commonSources.contains("kotlin/Function.kt"))
        #expect(manifest.commonSources.contains("kotlin/Unit.kt"))
        for declaration in manifest.declarations {
            let data = try JVMStdlibCatalog.read(declaration.path, commonSource: declaration.commonSource == true)
            #expect(!data.isEmpty)
            #expect(String(decoding: data, as: UTF8.self).contains("package "))
        }
        for stdlib in [false, true] {
            let options = CompilerOptions(moduleName: "Catalog", inputs: stdlib ? [] : ["main.kt"], outputPath: "/private/tmp/catalog.jar", emit: .jvmJar, target: .hostDefault(), stdlibOnly: stdlib)
            let context = CompilationContext(options: options, sourceManager: SourceManager(), diagnostics: DiagnosticEngine(), interner: StringInterner())
            try JVMPreparationPhase().run(context)
            #expect(!context.diagnostics.hasError)
            let paths = context.sourceManager.fileIDs().map { context.sourceManager.path(of: $0) }
            #expect(paths.contains("<kswiftk-jvm>/stdlib-bridges.kt") == stdlib)
            #expect(paths.contains("<kswiftk-jvm>/console.kt") == !stdlib)
            #expect(paths.contains("<kswiftk-jvm>/unit.kt") == !stdlib)
            if !stdlib {
                #expect(!paths.contains("<kswiftk-jvm>/path-functions.kt"))
                #expect(!paths.contains("<kswiftk-jvm>/kotlin-io-path.kt"))
                #expect(!paths.contains("<kswiftk-jvm>/path-predicates.kt"))
            }
            #expect(paths.contains { $0.hasSuffix("/Stdlib/kotlin/Unit.kt") } == stdlib)
        }
    }

    @Test
    func manifestDeclarationVirtualPathsAreUnique() throws {
        let manifestURL = try JVMStdlibCatalog.resourceRoot()
            .appendingPathComponent("jvm/manifest.json")
        let manifest = try JSONDecoder().decode(
            JVMStdlibCatalog.Manifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let paths = manifest.declarations.map(\.virtualPath)
        #expect(paths.count == Set(paths).count)
    }

    /// KUU-4586: racing PRs re-added identical top-level contracts in different
    /// declarations files (e.g. `ByteArray.decodeToString`), which makes
    /// consumer compiles fail with "Duplicate JVM-erased callable declaration
    /// in the same package scope." Pin that no two declaration files declare
    /// the same erased package-scope signature. Mirrors
    /// `hasSameJVMErasedCallableSignature`: receiver + value parameters
    /// compared after nullability/variance erasure, with each declaration's
    /// own type parameters treated as wildcards and `@JvmName` renaming
    /// respected. Type arguments are kept (the real check compares TypeIDs).
    @Test
    func declarationsHaveNoDuplicatePackageScopeSignatures() throws {
        let manifest = try JVMStdlibCatalog.manifest()
        var duplicates: [String] = []
        // A pair only clashes when both files are injected in the same
        // compile: excludeFromStdlibBuild entries only land in consumer
        // builds, onlyForStdlibBuild entries only in the stdlib-jar build.
        for context in ["stdlib", "consumer"] {
            var seen: [String: String] = [:]
            for declaration in manifest.declarations {
                if context == "stdlib" && declaration.excludeFromStdlibBuild == true { continue }
                if context == "consumer" && declaration.onlyForStdlibBuild == true { continue }
                let data = try JVMStdlibCatalog.read(declaration.path, commonSource: declaration.commonSource == true)
                let text = String(decoding: data, as: UTF8.self)
                var package = ""
                for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
                    let line = rawLine.trimmingCharacters(in: .whitespaces)
                    if line.hasPrefix("package ") {
                        package = String(line.dropFirst(8))
                        continue
                    }
                    // `external` declarations model existing JVM surface, not
                    // implementations that could clash; the real check ignores
                    // them too.
                    guard !rawLine.hasPrefix(" ") && !rawLine.hasPrefix("\t"),
                          line.contains("fun "),
                          let funRange = line.range(of: #"^(?:(?:public|private|internal|inline|operator|infix|tailrec|suspend)\s+)*fun\s+"#, options: .regularExpression)
                    else { continue }
                    var rest = Substring(line[funRange.upperBound...])
                    // Type parameters of this declaration are wildcards.
                    var typeParams: [String] = []
                    if rest.hasPrefix("<") {
                        var angle = 0
                        var close: String.Index? = nil
                        for index in rest.indices {
                            if rest[index] == "<" { angle += 1 }
                            if rest[index] == ">" { angle -= 1 }
                            if angle == 0 { close = index; break }
                        }
                        if let close {
                            typeParams = rest[rest.index(after: rest.startIndex)..<close].split(separator: ",").map {
                                String($0.trimmingCharacters(in: .whitespaces).split(separator: ":").first ?? "")
                            }
                            rest = rest[rest.index(after: close)...].drop(while: { $0 == " " })
                        }
                    }
                    // The parameter list opens at the first `(` at paren
                    // depth 0 that follows an identifier (skips receivers
                    // like `(suspend () -> T).startCoroutine`).
                    var depth = 0
                    var open: String.Index? = nil
                    var previous = rest.startIndex
                    for index in rest.indices {
                        defer { previous = index }
                        if rest[index] == "(" {
                            if depth == 0, index > rest.startIndex,
                               rest[previous].isLetter || rest[previous].isNumber
                                   || rest[previous] == "_" || rest[previous] == ">" {
                                open = index
                                break
                            }
                            depth += 1
                        }
                        if rest[index] == ")" { depth -= 1 }
                    }
                    guard let open else { continue }
                    let head = String(rest[..<open]).trimmingCharacters(in: .whitespaces)
                    var end: String.Index? = nil
                    for index in rest[open...].indices {
                        if rest[index] == "(" { depth += 1 }
                        if rest[index] == ")" { depth -= 1 }
                        if depth == 0 { end = index; break }
                    }
                    guard let end, end > open else { continue }
                    let params = String(rest[rest.index(after: open)..<end])
                    guard let nameRange = head.range(of: #"[A-Za-z_]\w*$"#, options: .regularExpression) else { continue }
                    let name = String(head[nameRange])
                    var receiver = String(head[..<nameRange.lowerBound])
                    if receiver.hasSuffix(".") { receiver = String(receiver.dropLast()) }
                    // Keep only the erased parameter type list.
                    var pieces: [String] = []
                    depth = 0
                    var inString = false
                    var current = ""
                    for char in params {
                        if char == "\"" { inString.toggle() }
                        if !inString {
                            if char == "(" { depth += 1 }
                            if char == ")" { depth -= 1 }
                            if char == "," && depth == 0 { pieces.append(current); current = ""; continue }
                        }
                        current.append(char)
                    }
                    pieces.append(current)
                    let paramTypes = pieces.map { piece -> String in
                        var p = piece.trimmingCharacters(in: .whitespaces)
                        let isVararg = p.hasPrefix("vararg ")
                        if isVararg { p = String(p.dropFirst(7)) }
                        if let eq = p.range(of: "=") { p = String(p[..<eq.lowerBound]) }
                        if let colon = p.range(of: ":") { p = String(p[colon.upperBound...]) }
                        return isVararg ? "vararg " + p : p
                    }
                    var key = package + "/" + receiver + "." + name + "(" + paramTypes.joined(separator: ",") + ")"
                    for param in typeParams {
                        key = key.replacingOccurrences(of: #"\b"# + param + #"\b"#, with: "*", options: .regularExpression)
                    }
                    key = key.replacingOccurrences(of: #"\b(out|in)\s+"#, with: "", options: .regularExpression)
                    key = key.replacingOccurrences(of: "?", with: "")
                    key = key.replacingOccurrences(of: " ", with: "")
                    key = key.replacingOccurrences(of: #"\bkotlin\.(?:collections\.|sequences\.|ranges\.|text\.)?(?=[A-Z])"#, with: "", options: .regularExpression)
                    if let owner = seen[key] {
                        duplicates.append(key + " in " + declaration.path + " duplicates " + owner)
                    } else {
                        seen[key] = declaration.path
                    }
                }
            }
        }
        #expect(duplicates.isEmpty, "\(duplicates)")
    }

    @Test
    func nominalNamesIncludeTypeAliases() throws {
        let options = CompilerOptions(moduleName: "Catalog", inputs: ["main.kt"], outputPath: "/private/tmp/catalog.jar", emit: .jvmJar, target: .hostDefault(), stdlibOnly: false)
        let context = CompilationContext(options: options, sourceManager: SourceManager(), diagnostics: DiagnosticEngine(), interner: StringInterner())
        try JVMPreparationPhase().run(context)
        #expect(!context.diagnostics.hasError)
        let names = try JVMStdlibCatalog.nominalNames(in: context)
        #expect(names.contains("java/lang/IllegalArgumentException"))
        #expect(names.contains("java/lang/IllegalAccessException"))
        #expect(names.contains("kotlin/text/Charset"))
    }
}
#endif
