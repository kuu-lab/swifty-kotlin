package golden.parser

class Outer { class Nested { class Deep } inner class Inn }
class WithFn { class Nested { } fun f() = 1 }
class WithClass { class Nested { } class C }
class WithVal { class Nested { } val p = 1 }
