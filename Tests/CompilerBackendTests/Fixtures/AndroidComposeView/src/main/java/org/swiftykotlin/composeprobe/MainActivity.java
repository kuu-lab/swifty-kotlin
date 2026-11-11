package org.swiftykotlin.composeprobe;

import android.os.Bundle;
import androidx.activity.ComponentActivity;
import androidx.compose.ui.platform.ComposeView;
import kotlin.Unit;

public final class MainActivity extends ComponentActivity {
    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        CounterRenderer renderer = new CounterRenderer();
        ComposeView view = new ComposeView(this);
        view.setContent((composer, changed) -> {
            CounterKt.Counter(renderer, composer, changed);
            return Unit.INSTANCE;
        });
        setContentView(view);
    }
}
