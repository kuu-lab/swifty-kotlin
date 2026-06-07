@testable import CompilerCore
import RuntimeABI
import XCTest

final class RuntimeABIExternalLinkValidationTests: XCTestCase {
    func testRegisteredSemaExternalLinkNamesExistInRuntimeABI() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)
        let runtimeABINames = Set(RuntimeABISpec.allFunctions.map(\.name))
        let linkNames = Set(sema.symbols.allSymbols().compactMap { symbol in
            sema.symbols.externalLinkName(for: symbol.id)
        }.filter { !$0.isEmpty }
            .map { loweredRuntimeLinkAlias[$0] ?? $0 })
        let missing = linkNames
            .subtracting(runtimeABINames)
            .subtracting(allowedCompilerExternalLinks)
            .sorted()

        XCTAssertTrue(
            missing.isEmpty,
            "Compiler synthetic externalLinkName values missing from RuntimeABISpec: \(missing.joined(separator: ", "))"
        )
    }

    func testKIRHardcodedRuntimeLinkNamesExistInRuntimeABI() throws {
        let runtimeABINames = Set(RuntimeABISpec.allFunctions.map(\.name))
        let compilerCore = packageRoot().appendingPathComponent("Sources/CompilerCore")
        let linkNames = try collectRuntimeLinkNameLiterals(
            under: [
                compilerCore.appendingPathComponent("KIR"),
                compilerCore.appendingPathComponent("Lowering"),
                compilerCore.appendingPathComponent("Sema"),
            ]
        )
        let resolvedLinkNames = Set(linkNames.map { loweredRuntimeLinkAlias[$0] ?? $0 })
        let missing = resolvedLinkNames
            .subtracting(runtimeABINames)
            .subtracting(allowedCompilerExternalLinks)
            .sorted()

        XCTAssertTrue(
            missing.isEmpty,
            "KIR runtime link name literals missing from RuntimeABISpec: \(missing.joined(separator: ", "))"
        )
    }

    private var loweredRuntimeLinkAlias: [String: String] {
        [
            // KIR keeps semantic String callee names; LLVM emission lowers these to flattened runtime ABI symbols.
            "kk_string_first": "kk_string_first_flat",
            "kk_string_firstOrNull": "kk_string_firstOrNull_flat",
            "kk_string_getOrNull": "kk_string_getOrNull_flat",
            "kk_string_isNotBlank": "kk_string_isNotBlank_flat",
            "kk_string_isNotEmpty": "kk_string_isNotEmpty_flat",
            "kk_string_last": "kk_string_last_flat",
            "kk_string_lastOrNull": "kk_string_lastOrNull_flat",
            "kk_string_single": "kk_string_single_flat",
            "kk_string_singleOrNull": "kk_string_singleOrNull_flat",
            "kk_string_toBoolean": "kk_string_toBoolean_flat",
            "kk_string_toBooleanStrict": "kk_string_toBooleanStrict_flat",
            "kk_string_toBooleanStrictOrNull": "kk_string_toBooleanStrictOrNull_flat",
            "kk_string_toByte": "kk_string_toByte_flat",
            "kk_string_toByteOrNull": "kk_string_toByteOrNull_flat",
            "kk_string_toByte_radix": "kk_string_toByte_radix_flat",
            "kk_string_toDouble": "kk_string_toDouble_flat",
            "kk_string_toDoubleOrNull": "kk_string_toDoubleOrNull_flat",
            "kk_string_toFloat": "kk_string_toFloat_flat",
            "kk_string_toFloatOrNull": "kk_string_toFloatOrNull_flat",
            "kk_string_toInt": "kk_string_toInt_flat",
            "kk_string_toIntOrNull": "kk_string_toIntOrNull_flat",
            "kk_string_toIntOrNull_radix": "kk_string_toIntOrNull_radix_flat",
            "kk_string_toInt_radix": "kk_string_toInt_radix_flat",
            "kk_string_toLong": "kk_string_toLong_flat",
            "kk_string_toLongOrNull": "kk_string_toLongOrNull_flat",
            "kk_string_toShort": "kk_string_toShort_flat",
            "kk_string_toShortOrNull": "kk_string_toShortOrNull_flat",
            "kk_string_toUByteOrNull_radix": "kk_string_toUByteOrNull_radix_flat",
            "kk_string_toUIntOrNull_radix": "kk_string_toUIntOrNull_radix_flat",
            "kk_string_toULongOrNull_radix": "kk_string_toULongOrNull_radix_flat",
            "kk_string_toUShortOrNull_radix": "kk_string_toUShortOrNull_radix_flat",
        ]
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
            "kk_uint",
            "kk_ulong",
            "kk_unknown_callable",
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
