@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-MISC: Consolidated Sema coverage for simple String extension
/// functions. A single `runSema(ctx)` resolves all source packages and each package
/// is checked for the absence of errors.
@Suite
struct StringMiscFunctionTests {
    @Test
    func testStringMiscFunctionsResolveInSource() throws {
        let sources: [String] = [
            """
            package sample0
            fun hasDigit(s: String): Boolean {
                return s.any { it.isDigit() }
            }

            fun hasUpperLiteral(): Boolean {
                return "Hello".any { it.isUpperCase() }
            }

            fun anyEqualsX(s: String): Boolean {
                return s.any { ch -> ch == 'x' }
            }

            fun emptyAny(): Boolean {
                return "".any { it == 'a' }
            }
            """,
            """
            package sample1
            fun hasSubstring(s: String): Boolean {
                return s.contains("hello")
            }

            fun emptyNeedleAlwaysMatches(s: String): Boolean {
                return s.contains("")
            }

            fun literalReceiverContains(): Boolean {
                return "hello world".contains("world")
            }

            fun hasSubstringIgnoreCase(s: String): Boolean {
                return s.contains("HELLO", true)
            }

            fun explicitCaseSensitive(s: String, needle: String): Boolean {
                return s.contains(needle, false)
            }

            fun namedIgnoreCase(s: String): Boolean {
                return s.contains("foo", ignoreCase = true)
            }

            fun substringViaInOperator(s: String, needle: String): Boolean {
                return needle in s
            }
            """,
            """
            package sample2
            fun stringEndsWithSuffix(s: String): Boolean {
                return s.endsWith("lin")
            }

            fun literalEndsWith(): Boolean {
                return "Kotlin".endsWith("lin")
            }

            fun literalEndsWithMismatch(): Boolean {
                return "Kotlin".endsWith("XYZ")
            }

            fun emptySuffixIsAlwaysTrue(s: String): Boolean {
                return s.endsWith("")
            }
            """,
            """
            package sample3
            fun firstChar(s: String): Char {
                return s.get(0)
            }

            fun charAt(s: String, i: Int): Char {
                return s[i]
            }

            fun firstOfHello(): Char {
                return "hello".get(0)
            }

            fun secondOfHello(): Char {
                return "hello"[1]
            }
            """,
            """
            package sample4
            fun findDigit(s: String): Int {
                return s.indexOfFirst { it.isDigit() }
            }

            fun findUpperLiteral(): Int {
                return "Hello".indexOfFirst { it.isUpperCase() }
            }

            fun findEqualsX(s: String): Int {
                return s.indexOfFirst { ch -> ch == 'x' }
            }

            fun emptyIndexOfFirst(): Int {
                return "".indexOfFirst { it == 'a' }
            }

            fun usesIndexResult(s: String): Boolean {
                val idx: Int = s.indexOfFirst { it == 'z' }
                return idx >= 0
            }

            fun findInCharSequence(cs: CharSequence): Int {
                return cs.indexOfFirst { it.isLetter() }
            }
            """,
            """
            package sample5
            fun findToken(s: String): Int {
                return s.indexOf("token")
            }

            fun findFromOffset(s: String): Int {
                return s.indexOf("token", 3)
            }

            fun findCaseInsensitive(s: String): Int {
                return s.indexOf("Token", 0, true)
            }

            fun findChar(s: String): Int {
                return s.indexOf('x')
            }

            fun findCharFromOffset(s: String): Int {
                return s.indexOf('x', 2)
            }

            fun findCharCaseInsensitive(s: String): Int {
                return s.indexOf('X', 0, true)
            }
            """,
            """
            package sample6
            fun findLastDigit(s: String): Int {
                return s.indexOfLast { it.isDigit() }
            }

            fun findLastUpperLiteral(): Int {
                return "Hello".indexOfLast { it.isUpperCase() }
            }

            fun findLastEqualsX(s: String): Int {
                return s.indexOfLast { ch -> ch == 'x' }
            }

            fun emptyIndexOfLast(): Int {
                return "".indexOfLast { it == 'a' }
            }

            fun usesIndexResult(s: String): Boolean {
                val idx: Int = s.indexOfLast { it == 'z' }
                return idx >= 0
            }

            fun findLastInCharSequence(cs: CharSequence): Int {
                return cs.indexOfLast { it.isLetter() }
            }
            """,
            """
            package sample7
            fun internString(s: String): String {
                return s.intern()
            }
            """,
            """
            package sample8
            fun isStringEmpty(s: String): Boolean {
                return s.isEmpty()
            }

            fun isEmptyLiteral(): Boolean {
                return "".isEmpty()
            }

            fun isNonEmptyLiteral(): Boolean {
                return "hello".isEmpty()
            }
            """,
            """
            package sample9
            fun splitToLines(s: String): List<String> {
                return s.lines()
            }

            fun firstLine(): String {
                return "a\\nb\\nc".lines().first()
            }

            fun printAll(s: String) {
                for (line in s.lines()) {
                    println(line)
                }
            }
            """,
            """
            package sample10
            fun rightPadDefault(s: String): String {
                return s.padEnd(8)
            }

            fun rightPadWithChar(s: String): String {
                return s.padEnd(8, '*')
            }

            fun rightPadShorterThanSource(): String {
                return "hello".padEnd(3)
            }

            fun rightPadExpression(value: Int): String {
                return value.toString().padEnd(6, '0')
            }
            """,
            """
            package sample11
            fun leftPadDefault(s: String): String {
                return s.padStart(8)
            }

            fun leftPadWithChar(s: String): String {
                return s.padStart(8, '*')
            }

            fun leftPadShorterThanSource(): String {
                return "hello".padStart(3)
            }

            fun leftPadExpression(value: Int): String {
                return value.toString().padStart(6, '0')
            }
            """,
            """
            package sample12
            fun stripSuffix(s: String): String {
                return s.removeSuffix("World")
            }

            fun removeSuffixLiteral(): String {
                return "HelloWorld".removeSuffix("World")
            }

            fun removeSuffixNoMatch(): String {
                return "HelloWorld".removeSuffix("Earth")
            }

            fun removeSuffixEmpty(): String {
                return "".removeSuffix("suffix")
            }

            fun removeSuffixExact(): String {
                return "suffix".removeSuffix("suffix")
            }

            fun removeSuffixOnExpression(value: Int): String {
                return value.toString().removeSuffix("0")
            }
            """,
            """
            package sample13
            fun sliceByRange(s: String): String {
                return s.slice(1..3)
            }

            fun sliceByUntil(s: String): String {
                return s.slice(0 until 5)
            }

            fun sliceByList(s: String): String {
                return s.slice(listOf(0, 2, 4))
            }

            fun sliceViaVar(s: String): String {
                val r = 1..3
                return s.slice(r)
            }
            """,
            """
            package sample14
            fun afterStringDelimiter(s: String): String {
                return s.substringAfter(".")
            }

            fun afterStringDelimiterWithDefault(s: String, missing: String): String {
                return s.substringAfter(".", missing)
            }

            fun afterCharDelimiter(s: String): String {
                return s.substringAfter('.')
            }

            fun afterCharDelimiterWithDefault(s: String, missing: String): String {
                return s.substringAfter('.', missing)
            }

            fun afterLiteralReceiver(): String {
                return "hello.world.kt".substringAfter(".")
            }

            fun afterLiteralReceiverChar(): String {
                return "hello.world.kt".substringAfter('.')
            }

            fun afterMissingValueLiteral(): String {
                return "no-delimiter-here".substringAfter("@", "fallback")
            }
            """,
            """
            package sample15
            fun lastSegmentString(path: String): String {
                return path.substringAfterLast(".")
            }

            fun explicitFallbackString(path: String): String {
                return path.substringAfterLast(".", "<none>")
            }

            fun lastSegmentChar(path: String): String {
                return path.substringAfterLast('.')
            }

            fun explicitFallbackChar(path: String): String {
                return path.substringAfterLast('.', "<none>")
            }

            fun useLiteral(): String = "hello.world.kt".substringAfterLast(".")
            fun useLiteralChar(): String = "hello.world.kt".substringAfterLast('.')
            fun useLiteralWithFallback(): String = "no-delimiter".substringAfterLast(":", "<absent>")
            fun useLiteralCharWithFallback(): String = "no-delimiter".substringAfterLast(':', "<absent>")

            fun useNamedString(path: String): String {
                return path.substringAfterLast(delimiter = ".", missingDelimiterValue = "<none>")
            }

            fun useNamedChar(path: String): String {
                return path.substringAfterLast(delimiter = '.', missingDelimiterValue = "<none>")
            }
            """,
            """
            package sample16
            fun firstSegmentString(path: String): String {
                return path.substringBefore(".")
            }

            fun explicitFallbackString(path: String): String {
                return path.substringBefore(".", "<none>")
            }

            fun firstSegmentChar(path: String): String {
                return path.substringBefore('.')
            }

            fun explicitFallbackChar(path: String): String {
                return path.substringBefore('.', "<none>")
            }

            fun useLiteral(): String = "hello.world.kt".substringBefore(".")
            fun useLiteralChar(): String = "hello.world.kt".substringBefore('.')
            fun useLiteralWithFallback(): String = "no-delimiter".substringBefore(":", "<absent>")
            fun useLiteralCharWithFallback(): String = "no-delimiter".substringBefore(':', "<absent>")

            fun useNamedString(path: String): String {
                return path.substringBefore(delimiter = ".", missingDelimiterValue = "<none>")
            }

            fun useNamedChar(path: String): String {
                return path.substringBefore(delimiter = '.', missingDelimiterValue = "<none>")
            }
            """,
            """
            package sample17
            fun headSegmentString(path: String): String {
                return path.substringBeforeLast(".")
            }

            fun explicitFallbackString(path: String): String {
                return path.substringBeforeLast(".", "<none>")
            }

            fun headSegmentChar(path: String): String {
                return path.substringBeforeLast('.')
            }

            fun explicitFallbackChar(path: String): String {
                return path.substringBeforeLast('.', "<none>")
            }

            fun useLiteral(): String = "hello.world.kt".substringBeforeLast(".")
            fun useLiteralChar(): String = "hello.world.kt".substringBeforeLast('.')
            fun useLiteralWithFallback(): String = "no-delimiter".substringBeforeLast(":", "<absent>")
            fun useLiteralCharWithFallback(): String = "no-delimiter".substringBeforeLast(':', "<absent>")

            fun useNamedString(path: String): String {
                return path.substringBeforeLast(delimiter = ".", missingDelimiterValue = "<none>")
            }

            fun useNamedChar(path: String): String {
                return path.substringBeforeLast(delimiter = '.', missingDelimiterValue = "<none>")
            }
            """,
            """
            package sample18
            fun explode(s: String): MutableList<Char> {
                return s.toMutableList()
            }

            fun explodeLiteral(): MutableList<Char> {
                return "hello".toMutableList()
            }

            fun appendBang(s: String): Int {
                val chars = s.toMutableList()
                chars.add('!')
                return chars.size
            }
            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let names = [
                "StringAnyFunction",
                "StringContainsFunction",
                "StringEndsWithFunction",
                "StringGetFunction",
                "StringIndexOfFirstFunction",
                "StringIndexOfFunction",
                "StringIndexOfLastFunction",
                "StringInternFunction",
                "StringIsEmptyFunction",
                "StringLinesFunction",
                "StringPadEndFunction",
                "StringPadStartFunction",
                "StringRemoveSuffixFunction",
                "StringSliceFunction",
                "StringSubstringAfterFunction",
                "StringSubstringAfterLastFunction",
                "StringSubstringBeforeFunction",
                "StringSubstringBeforeLastFunction",
                "StringToMutableListFunction"
            ]
            for (index, name) in names.enumerated() {
                let path = paths[index]
                let pathDiagnostics = diagnosticsForPath(path, in: ctx)
                let errors = pathDiagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected \(name) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )
            }
        }
    }
}
