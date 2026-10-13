@testable import CompilerCore
import Testing

@Suite
struct AnnotationStringConcatenationTests {
    @Test(arguments: [
        (#""A+B" + "C""#, "A+BC"),
        (#""""A+B""" + "C""#, "A+BC"),
        (#""" + "C""#, "C"),
        (#""""""" + """B""""#, "B"),
        (#"$$"A+B" + "C""#, "A+BC"),
        (#"$$"""A+B""" + "C""#, "A+BC"),
        (#"$$"" + "C""#, "C"),
        (#"$$"""""" + "C""#, "C"),
        (#""A\nB" + "C""#, "A\nBC"),
        (#""""A\nB""" + "C""#, #"A\nBC"#),
        (#""A\"+B" + "C""#, "A\"+BC"),
        (#""+" + """#, "+"),
        (#""" + "" + """#, ""),
        (#""\uD800" + "\uDC00""#, "𐀀")
    ])
    func foldsLiteralOperandsBeforeTokenTextLosesTheirBoundaries(expression: String, expected: String) throws {
        let (tokens, interner, diagnostics) = lex("@Marker(message = \(expression)) class Subject")
        #expect(!diagnostics.hasError)
        let parsed = try #require(AnnotationParsingSupport.parseAnnotation(
            from: tokens, start: 0, interner: interner, allowUseSiteTarget: true
        ))
        let argument = try #require(parsed.annotation.arguments.first)
        let value = SemaAnnotationArgument.value(argument, parameterName: "message")
        let literal = try #require(extractKotlinStringLiteralContent(value))
        #expect(decodeKotlinStringEscapes(literal.content) == expected)
    }

    @Test(arguments: [#""A" + name"#, #"name + "B""#, #""A+B""#, #""A${name}" + "B""#])
    func preservesNonliteralExpressionsAndExistingSingleLiteralMetadata(expression: String) throws {
        let (tokens, interner, _) = lex("@Marker(message = \(expression)) class Subject")
        let parsed = try #require(AnnotationParsingSupport.parseAnnotation(
            from: tokens, start: 0, interner: interner, allowUseSiteTarget: true
        ))
        let argument = try #require(parsed.annotation.arguments.first)
        #expect(!argument.contains(#"\u0041"#))
    }
}
