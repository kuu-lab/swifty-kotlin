@testable import CompilerCore
import TestStdlibCache
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func testInheritedProtectedMemberExtensionDelegates(useArtifact: Bool, optimization: Int) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        try compileAndRunKotlinSources(
            [
                """
                import kotlin.reflect.KProperty

                class Token(val name: String)
                open class Grammar {
                    val registeredTokens = mutableListOf<Token>()
                    protected operator fun Token.provideDelegate(
                        thisRef: Grammar, property: KProperty<*>
                    ): Token {
                        registeredTokens.add(this)
                        return this
                    }
                    protected operator fun Token.getValue(
                        thisRef: Grammar, property: KProperty<*>
                    ): Token = this
                }
                class TokenLanguage : Grammar() {
                    val token by Token("num")
                }

                class Parser<out T>(val name: String)
                open class ParserGrammar<out T> {
                    val registeredParsers = mutableListOf<Parser<*>>()
                    protected operator fun <P> Parser<P>.provideDelegate(
                        thisRef: ParserGrammar<*>, property: KProperty<*>
                    ): Parser<P> {
                        registeredParsers.add(this)
                        return this
                    }
                    protected operator fun <P> Parser<P>.getValue(
                        thisRef: ParserGrammar<*>, property: KProperty<*>
                    ): Parser<P> = this
                }
                class ParserLanguage : ParserGrammar<String>() {
                    val root: Parser<String> by Parser<String>("root")
                }

                fun main() {
                    val language = TokenLanguage()
                    check(language.registeredTokens.size == 1)
                    val parserLanguage = ParserLanguage()
                    check(parserLanguage.registeredParsers.size == 1)
                    check(parserLanguage.root.name == "root")
                    println(language.token.name)
                }
                """
            ],
            expectedOutput: "num\n",
            moduleName: "KUU1915InheritedProtectedMemberExtensions",
            allowDefaultStdlibLibrary: useArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: "",
            requireNoCompilerDiagnostics: true
        )
    }
}
