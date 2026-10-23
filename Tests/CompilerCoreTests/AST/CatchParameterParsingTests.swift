#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct CatchParameterParsingTests {
    @Test(arguments: [
        "try { } catch { }",
        "try { } catch () { }",
        "try { } catch (e) { }",
        "try { } catch (e, f) { }",
        "try { } catch (e: Exception, f: Exception) { }",
        "try { } catch (e: Exception { }",
        "try { } catch finally { }",
    ])
    func rejectsMalformedCatchParameter(_ source: String) throws {
        let lexed = lex(source)
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )

        _ = parser.parse()

        #expect(lexed.diagnostics.diagnostics.contains {
            $0.severity == .error && $0.code == "KSWIFTK-PARSE-0028"
        })
    }

    @Test(arguments: [
        "try { } catch (e: Exception) { }",
        "try { } catch (e: Exception) { } finally { }",
        "try { } catch (e: Exception) { } catch (f: Throwable) { }",
        "try { } catch (@Suppress(\"x\") e: Exception) { }",
        "try { } catch (e: Map<K, V>) { }",
    ])
    func acceptsWellFormedCatchParameter(_ source: String) throws {
        let lexed = lex(source)
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )

        #expect(parser.parse() != nil)
        #expect(lexed.diagnostics.diagnostics.isEmpty)
    }
}
#endif
