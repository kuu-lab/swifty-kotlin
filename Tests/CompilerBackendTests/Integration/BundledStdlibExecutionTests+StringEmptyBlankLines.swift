import Testing

// SLOP-007 regression: String and non-String CharSequence receivers must share
// the source-backed conversion and line-separator implementation.
extension BundledStdlibExecutionTests {
    @Test
    func testStringAndCharSequenceEmptyBlankAndLinesPreserveKotlinSemantics() throws {
        try compileAndRunKotlin(
            """
            fun escape(value: String): String {
                return value
                    .replace("\\r", "<CR>")
                    .replace("\\n", "<LF>")
                    .replace("\\t", "<TAB>")
            }

            fun formatLines(values: List<String>): String {
                return values.map { escape(it) }.joinToString("|", "[", "]")
            }

            fun probe(label: String, value: CharSequence) {
                val emptyResult = value.ifEmpty { "<empty>" }
                val blankResult = value.ifBlank { "<blank>" }
                println(
                    label +
                        ":isEmpty=" + value.isEmpty() +
                        ",isBlank=" + value.isBlank() +
                        ",ifEmpty=" + escape(emptyResult.toString()) +
                        ",ifBlank=" + escape(blankResult.toString()) +
                        ",lines=" + formatLines(value.lines()) +
                        ",sequence=" + formatLines(value.lineSequence().toList())
                )
            }

            fun main() {
                probe("string-empty", "")
                probe("string-lf", "a\\nb")
                probe("string-crlf", "a\\r\\nb")
                probe("string-cr", "a\\rb")
                probe("charsequence-empty", StringBuilder(""))
                probe("charsequence-blank", StringBuilder(" \\t\\r\\n"))
                probe("charsequence-crlf", StringBuilder("a\\r\\nb"))
                probe("charsequence-cr", StringBuilder("a\\rb"))
            }
            """,
            expectedOutput: """
            string-empty:isEmpty=true,isBlank=true,ifEmpty=<empty>,ifBlank=<blank>,lines=[],sequence=[]
            string-lf:isEmpty=false,isBlank=false,ifEmpty=a<LF>b,ifBlank=a<LF>b,lines=[a|b],sequence=[a|b]
            string-crlf:isEmpty=false,isBlank=false,ifEmpty=a<CR><LF>b,ifBlank=a<CR><LF>b,lines=[a|b],sequence=[a|b]
            string-cr:isEmpty=false,isBlank=false,ifEmpty=a<CR>b,ifBlank=a<CR>b,lines=[a|b],sequence=[a|b]
            charsequence-empty:isEmpty=true,isBlank=true,ifEmpty=<empty>,ifBlank=<blank>,lines=[],sequence=[]
            charsequence-blank:isEmpty=false,isBlank=true,ifEmpty= <TAB><CR><LF>,ifBlank=<blank>,lines=[ <TAB>|],sequence=[ <TAB>|]
            charsequence-crlf:isEmpty=false,isBlank=false,ifEmpty=a<CR><LF>b,ifBlank=a<CR><LF>b,lines=[a|b],sequence=[a|b]
            charsequence-cr:isEmpty=false,isBlank=false,ifEmpty=a<CR>b,ifBlank=a<CR>b,lines=[a|b],sequence=[a|b]
            """ + "\n"
        )
    }
}
