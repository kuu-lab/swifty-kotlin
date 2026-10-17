import java.io.ByteArrayOutputStream;
import java.io.PrintStream;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.junit.platform.engine.TestExecutionResult;
import org.junit.platform.engine.DiscoverySelector;
import org.junit.platform.engine.support.descriptor.MethodSource;
import org.junit.platform.launcher.TestExecutionListener;
import org.junit.platform.launcher.TestIdentifier;
import org.junit.platform.launcher.TestPlan;
import org.junit.platform.launcher.core.LauncherDiscoveryRequestBuilder;
import org.junit.platform.launcher.core.LauncherFactory;
import static org.junit.platform.engine.discovery.DiscoverySelectors.selectClasspathRoots;
import static org.junit.platform.engine.discovery.DiscoverySelectors.selectMethod;

/** Java 21 source-mode runner: the original test classes and assertions are unchanged. */
class JvmReferenceRunner {
    private static String json(Object value) {
        if (value == null) return "null";
        if (value instanceof Boolean || value instanceof Number) return value.toString();
        if (value instanceof Map<?, ?> map) {
            var fields = new ArrayList<String>();
            map.forEach((key, item) -> fields.add(json(key.toString()) + ":" + json(item)));
            return "{" + String.join(",", fields) + "}";
        }
        if (value instanceof Iterable<?> items) {
            var fields = new ArrayList<String>();
            items.forEach(item -> fields.add(json(item)));
            return "[" + String.join(",", fields) + "]";
        }
        StringBuilder result = new StringBuilder("\"");
        value.toString().codePoints().forEach(c -> {
            switch (c) {
                case '"' -> result.append("\\\"");
                case '\\' -> result.append("\\\\");
                case '\n' -> result.append("\\n");
                case '\r' -> result.append("\\r");
                case '\t' -> result.append("\\t");
                default -> {
                    if (c < 32) result.append(String.format("\\u%04x", c));
                    else result.appendCodePoint(c);
                }
            }
        });
        return result.append('"').toString();
    }

    private static Map<String, Object> describe(TestIdentifier test) {
        var row = new LinkedHashMap<String, Object>();
        row.put("execution_id", test.getUniqueId());
        row.put("display_name", test.getDisplayName());
        if (test.getSource().orElse(null) instanceof MethodSource source) {
            Method method = source.getJavaMethod();
            row.put("concrete_class", source.getClassName());
            row.put("declaring_class", method.getDeclaringClass().getName());
            row.put("method_name", source.getMethodName());
            row.put("parameter_types", source.getMethodParameterTypes());
        }
        return row;
    }

    public static void main(String[] args) throws Exception {
        if (args.length < 2 || args.length > 4) {
            throw new IllegalArgumentException("test jar, output directory, optional selected-methods file, and optional contract-probe class required");
        }
        Path output = Path.of(args[1]);
        Files.createDirectories(output);
        var launcher = LauncherFactory.create();
        var requestBuilder = LauncherDiscoveryRequestBuilder.request();
        if (args.length == 2) {
            requestBuilder.selectors(selectClasspathRoots(java.util.Set.of(Path.of(args[0]))));
        } else {
            var selectors = new ArrayList<DiscoverySelector>();
            var selectedMethods = new java.util.HashSet<String>();
            for (String line : Files.readAllLines(Path.of(args[2]), StandardCharsets.UTF_8)) {
                if (line.isBlank()) continue;
                String[] parts = line.split("\\t", -1);
                if (parts.length != 2 || parts[0].isBlank() || parts[1].isBlank()) {
                    throw new IllegalArgumentException("selected-methods file must contain class<TAB>method rows");
                }
                if (!selectedMethods.add(parts[0] + "#" + parts[1])) {
                    throw new IllegalArgumentException("duplicate selected method: " + line);
                }
                selectors.add(selectMethod(parts[0], parts[1]));
            }
            if (selectors.isEmpty()) throw new IllegalArgumentException("selected-methods file is empty");
            requestBuilder.selectors(selectors);
        }
        var request = requestBuilder
            .filters(org.junit.platform.engine.discovery.ClassNameFilter.includeClassNamePatterns(".*"))
            .configurationParameter("junit.jupiter.execution.parallel.enabled", "false")
            .build();
        TestPlan plan = launcher.discover(request);
        var discovered = new ArrayList<Map<String, Object>>();
        plan.getRoots().forEach(root -> plan.getDescendants(root).stream()
            .filter(TestIdentifier::isTest).forEach(test -> discovered.add(describe(test))));
        discovered.sort(Comparator.comparing(row -> row.get("execution_id").toString()));
        Files.writeString(output.resolve("discovered.json"), json(discovered) + "\n");
        if (discovered.isEmpty()) throw new IllegalStateException("no upstream tests discovered");

        var originalOut = System.out;
        var originalErr = System.err;
        var results = new ArrayList<Map<String, Object>>();
        launcher.registerTestExecutionListeners(new TestExecutionListener() {
            ByteArrayOutputStream stdout;
            ByteArrayOutputStream stderr;
            String active;
            long started;

            @Override public void executionStarted(TestIdentifier test) {
                if (!test.isTest()) return;
                if (active != null) throw new IllegalStateException("overlapping test execution");
                active = test.getUniqueId();
                started = System.nanoTime();
                stdout = new ByteArrayOutputStream();
                stderr = new ByteArrayOutputStream();
                System.setOut(new PrintStream(stdout, true, StandardCharsets.UTF_8));
                System.setErr(new PrintStream(stderr, true, StandardCharsets.UTF_8));
            }

            @Override public void executionSkipped(TestIdentifier test, String reason) {
                if (!test.isTest()) return;
                var row = describe(test);
                row.put("status", "SKIP");
                row.put("reason", reason);
                results.add(row);
            }

            @Override public void executionFinished(TestIdentifier test, TestExecutionResult result) {
                if (!test.isTest()) {
                    if (result.getStatus() != TestExecutionResult.Status.SUCCESSFUL) {
                        var row = describe(test);
                        row.put("status", "CONTAINER_ERROR");
                        row.put("exception_type", result.getThrowable().map(t -> t.getClass().getName()).orElse(null));
                        results.add(row);
                    }
                    return;
                }
                System.setOut(originalOut);
                System.setErr(originalErr);
                var row = describe(test);
                row.put("status", switch (result.getStatus()) {
                    case SUCCESSFUL -> "PASS";
                    case ABORTED -> "SKIP";
                    case FAILED -> "FAIL";
                });
                row.put("elapsed_seconds", (System.nanoTime() - started) / 1e9);
                row.put("stdout", stdout.toString(StandardCharsets.UTF_8));
                row.put("stderr", stderr.toString(StandardCharsets.UTF_8));
                row.put("exception_type", result.getThrowable().map(t -> t.getClass().getName()).orElse(null));
                row.put("exception_message", result.getThrowable().map(Throwable::getMessage).orElse(null));
                if (result.getThrowable().isPresent()) {
                    var trace = new ByteArrayOutputStream();
                    result.getThrowable().get().printStackTrace(new PrintStream(trace));
                    row.put("exception_stacktrace", trace.toString(StandardCharsets.UTF_8));
                }
                results.add(row);
                active = null;
            }
        });
        launcher.execute(plan);
        results.sort(Comparator.comparing(row -> row.get("execution_id").toString()));
        Files.writeString(output.resolve("results.json"), json(results) + "\n");
        long passed = results.stream().filter(row -> "PASS".equals(row.get("status"))).count();
        originalOut.println(json(Map.of("discovered", discovered.size(), "executed", results.size(), "passed", passed)));
        if (passed != discovered.size() || results.size() != discovered.size()) System.exit(1);
        if (args.length == 4) {
            Class<?> probe = Class.forName(args[3]);
            probe.getMethod("runKuu2563ApiContractProbe").invoke(null);
        }
    }
}
