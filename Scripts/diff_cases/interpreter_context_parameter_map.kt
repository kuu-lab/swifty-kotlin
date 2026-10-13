package design_patterns

class InterpreterContext {
    private val variables = mutableMapOf<String, Int>()

    fun putVariable(key: String, value: Int) {
        variables[key] = value
    }

    fun fetchVariable(key: String): Int = variables[key] ?: 0
}

interface InterpreterExpression {
    fun interpret(context: InterpreterContext)
}

class SetIntVariableExpression(
    private val key: String,
    private val intValue: Int
) : InterpreterExpression {
    override fun interpret(context: InterpreterContext) {
        context.putVariable(key = key, value = intValue)
    }
}

class PerformExpression(private vararg val expressions: InterpreterExpression) : InterpreterExpression {
    override fun interpret(context: InterpreterContext) {
        expressions.forEach { it.interpret(context) }
    }
}

class AddVariablesExpression(
    private val key0: String,
    private val key1: String,
    private val result: String
) : InterpreterExpression {
    override fun interpret(context: InterpreterContext) {
        context.putVariable(
            key = result,
            value = context.fetchVariable(key0) + context.fetchVariable(key1)
        )
    }
}

class MultipleVariablesExpression(
    private val key0: String,
    private val key1: String,
    private val result: String
) : InterpreterExpression {
    override fun interpret(context: InterpreterContext) {
        context.putVariable(
            key = result,
            value = context.fetchVariable(key0) * context.fetchVariable(key1)
        )
    }
}

fun writeViaContext(context: InterpreterContext, key: String, value: Int): Int {
    context.putVariable(key = key, value = value)
    return context.fetchVariable(key)
}

fun writeViaCtx(ctx: InterpreterContext, key: String, value: Int): Int {
    ctx.putVariable(key = key, value = value)
    return ctx.fetchVariable(key)
}

fun localContextWrite(): Int {
    val context = InterpreterContext()
    context.putVariable(key = "local", value = 23)
    return context.fetchVariable("local")
}

fun namedContextValue(context: Int): Int = context

fun main() {
    val expression = PerformExpression(
        SetIntVariableExpression("x", 10),
        SetIntVariableExpression("y", 20),
        AddVariablesExpression("x", "y", "sum"),
        SetIntVariableExpression("d", 5),
        MultipleVariablesExpression("sum", "d", "result")
    )
    val context = InterpreterContext()
    expression.interpret(context)

    println("x=" + context.fetchVariable("x"))
    println("y=" + context.fetchVariable("y"))
    println("sum=" + context.fetchVariable("sum"))
    println("d=" + context.fetchVariable("d"))
    println("result=" + context.fetchVariable("result"))
    println("override=" + writeViaContext(context, "override", 17))
    println("ctx=" + writeViaCtx(context, "ctx", 19))
    println("local=" + localContextWrite())
    println("named=" + namedContextValue(context = 42))
}
