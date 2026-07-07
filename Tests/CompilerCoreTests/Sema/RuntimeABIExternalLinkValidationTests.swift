@testable import CompilerCore
import RuntimeABI
import Foundation
import Testing

@Suite
struct RuntimeABIExternalLinkValidationTests {
    @Test func testRegisteredSemaExternalLinkNamesExistInRuntimeABI() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let runtimeABINames = Set(RuntimeABISpec.allFunctions.map(\.name))
        let linkNames = Set(sema.symbols.allSymbols().compactMap { symbol in
            sema.symbols.externalLinkName(for: symbol.id)
        }.filter { !$0.isEmpty })
        let missing = linkNames
            .subtracting(runtimeABINames)
            .subtracting(allowedCompilerExternalLinks)
            .sorted()

        #expect(
            missing.isEmpty,
            Comment(rawValue: "Compiler synthetic externalLinkName values missing from RuntimeABISpec: \(missing.joined(separator: ", "))")
        )
    }

    @Test func testKIRHardcodedRuntimeLinkNamesExistInRuntimeABI() throws {
        let runtimeABINames = Set(RuntimeABISpec.allFunctions.map(\.name))
        let compilerCore = packageRoot().appendingPathComponent("Sources/CompilerCore")
        let linkNames = try collectRuntimeLinkNameLiterals(
            under: [
                compilerCore.appendingPathComponent("KIR"),
                compilerCore.appendingPathComponent("Lowering"),
                compilerCore.appendingPathComponent("Sema"),
            ]
        )
        let resolvedLinkNames = Set(linkNames)
        let missing = resolvedLinkNames
            .subtracting(runtimeABINames)
            .subtracting(allowedCompilerExternalLinks)
            .sorted()

        #expect(
            missing.isEmpty,
            Comment(rawValue: "KIR runtime link name literals missing from RuntimeABISpec: \(missing.joined(separator: ", "))")
        )
    }

    @Test func testBundledKsSymbolNameDeclarationsMatchRuntimeABIArity() throws {
        let annotatedDeclarations = try collectBundledKsSymbolNameDeclarations()
        let runtimeABIByName = Dictionary(grouping: RuntimeABISpec.allFunctions, by: \.name)
        var failures: [String] = []

        for declaration in annotatedDeclarations.sorted(by: { $0.linkName < $1.linkName }) {
            guard let specs = runtimeABIByName[declaration.linkName], !specs.isEmpty else {
                failures.append("\(declaration.linkName) in \(declaration.relativePath) is missing from RuntimeABISpec")
                continue
            }
            if !specs.contains(where: { $0.parameters.count == declaration.arity }) {
                let arities = specs.map { "\($0.parameters.count)" }.sorted().joined(separator: ", ")
                failures.append(
                    "\(declaration.linkName) in \(declaration.relativePath) has Kotlin arity \(declaration.arity), RuntimeABI arities [\(arities)]"
                )
            }
        }

        #expect(!annotatedDeclarations.isEmpty, "@KsSymbolName coverage should not be empty")
        #expect(
            failures.isEmpty,
            Comment(rawValue: "Bundled @KsSymbolName declarations disagree with RuntimeABISpec: \(failures.joined(separator: "; "))")
        )
    }

    private var allowedCompilerExternalLinks: Set<String> {
        [
            "kk_for_lowered",
            "kk_int",
            "kk_int_narrow",
            "kk_uint_narrow",
            "kk_lambda_invoke",
            "kk_long",
            "kk_op_add",
            "kk_op_and",
            "kk_op_ishl",
            "kk_op_ishr",
            "kk_op_iushr",
            "kk_op_lshl",
            "kk_op_lshr",
            "kk_op_lushr",
            "kk_op_mul",
            "kk_op_or",
            "kk_op_sub",
            "kk_op_uadd",
            "kk_op_udiv",
            "kk_op_uge",
            "kk_op_ugt",
            "kk_op_ule",
            "kk_op_ult",
            "kk_op_uminus",
            "kk_op_umul",
            "kk_op_uplus",
            "kk_op_urem",
            "kk_op_usub",
            "kk_program_main",
            "kk_string_length",
            "kk_string_struct_get_length",
            "kk_uint",
            "kk_ulong",
            "kk_unknown_callable",
            "__string_struct_get_length",
        ]
    }

    private func packageRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func collectRuntimeLinkNameLiterals(under roots: [URL]) throws -> Set<String> {
        var names: Set<String> = []
        for root in roots {
            names.formUnion(try collectRuntimeLinkNameLiterals(under: root))
        }
        return names
    }

    private func collectRuntimeLinkNameLiterals(under root: URL) throws -> Set<String> {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var names: Set<String> = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            names.formUnion(runtimeLinkNameLiterals(in: source))
        }
        return names
    }

    private struct BundledKsSymbolNameDeclaration {
        let linkName: String
        let arity: Int
        let relativePath: String
    }

    private func collectBundledKsSymbolNameDeclarations() throws -> [BundledKsSymbolNameDeclaration] {
        let stdlibRoot = packageRoot().appendingPathComponent("Sources/CompilerCore/Stdlib")
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: stdlibRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var declarations: [BundledKsSymbolNameDeclaration] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "kt" {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let relativePath = fileURL.path.replacingOccurrences(of: stdlibRoot.path + "/", with: "")
            declarations.append(contentsOf: bundledKsSymbolNameDeclarations(in: source, relativePath: relativePath))
        }
        return declarations
    }

    private func bundledKsSymbolNameDeclarations(
        in source: String,
        relativePath: String
    ) -> [BundledKsSymbolNameDeclaration] {
        var declarations: [BundledKsSymbolNameDeclaration] = []
        var pendingLinkNames: [String] = []
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for (index, line) in lines.enumerated() {
            if let linkName = ksSymbolNameArgument(in: line) {
                pendingLinkNames.append(linkName)
                continue
            }
            guard !pendingLinkNames.isEmpty,
                  let functionHeader = functionHeader(startingAt: index, in: lines),
                  let arity = functionParameterArity(in: functionHeader)
            else {
                continue
            }
            for linkName in pendingLinkNames {
                declarations.append(
                    BundledKsSymbolNameDeclaration(
                        linkName: linkName,
                        arity: arity,
                        relativePath: relativePath
                    )
                )
            }
            pendingLinkNames.removeAll()
        }

        return declarations
    }

    private func ksSymbolNameArgument(in line: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"@KsSymbolName\(\s*(?:name\s*=\s*)?"([^"]+)"\s*\)"#) else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let valueRange = Range(match.range(at: 1), in: line)
        else {
            return nil
        }
        return String(line[valueRange])
    }

    private func functionHeader(startingAt index: Int, in lines: [String]) -> String? {
        var header = ""
        for line in lines[index...] {
            header += " " + line.trimmingCharacters(in: .whitespacesAndNewlines)
            if header.contains(")") {
                break
            }
        }
        return header.contains(" fun ") || header.trimmingCharacters(in: .whitespaces).hasPrefix("fun ")
            ? header
            : nil
    }

    private func functionParameterArity(in header: String) -> Int? {
        guard let funRange = header.range(of: "fun ") else {
            return nil
        }
        let suffix = header[funRange.upperBound...]
        guard let openParen = suffix.firstIndex(of: "(") else {
            return nil
        }

        var parenDepth = 0
        var closeParen: String.Index?
        var index = openParen
        while index < suffix.endIndex {
            let character = suffix[index]
            if character == "(" {
                parenDepth += 1
            } else if character == ")" {
                parenDepth -= 1
                if parenDepth == 0 {
                    closeParen = index
                    break
                }
            }
            index = suffix.index(after: index)
        }
        guard let closeParen else {
            return nil
        }

        let parameters = suffix[suffix.index(after: openParen)..<closeParen]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !parameters.isEmpty else {
            return 0
        }

        var count = 1
        var nestedParens = 0
        var nestedAngles = 0
        for character in parameters {
            switch character {
            case "(":
                nestedParens += 1
            case ")":
                nestedParens -= 1
            case "<":
                nestedAngles += 1
            case ">" where nestedAngles > 0:
                nestedAngles -= 1
            case "," where nestedParens == 0 && nestedAngles == 0:
                count += 1
            default:
                break
            }
        }
        return count
    }

    private func runtimeLinkNameLiterals(in source: String) -> Set<String> {
        let patterns = [
            #"interner\.intern\("(kk_[A-Za-z0-9_]+)"\)"#,
            #"(?:==|!=)\s*"(kk_[A-Za-z0-9_]+)""#,
            // Catch kk_ literals stored in variables ending in "Name" (e.g. createCalleeName: "kk_...")
            #"\w+Name\s*:\s*"(kk_[A-Za-z0-9_]+)""#,
        ]
        var names: Set<String> = []
        let sourceRange = NSRange(source.startIndex..<source.endIndex, in: source)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            for match in regex.matches(in: source, range: sourceRange) {
                guard let matchRange = Range(match.range(at: 1), in: source) else {
                    continue
                }
                names.insert(String(source[matchRange]))
            }
        }
        return names
    }
}
