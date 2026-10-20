package com.opencode.mithermal;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.os.Bundle;
import android.util.Log;
import android.webkit.JavascriptInterface;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * MiThermal 温控面板
 *
 * 一个纯 WebView 壳：界面是 assets/index.html，
 * 通过 Native.exec() 以 root 身份调用 MiThermalTuner 模块的 mt 命令。
 */
public class MainActivity extends Activity {

    private static final String TAG = "MiThermal";
    private static final String MT = "/data/adb/modules/mi_thermal_tuner/bin/mt";

    /** 允许执行的 mt 子命令白名单（防止通过注入执行任意命令） */
    private static final String[] ALLOWED = {
            "json", "json.scenarios", "json.profiles", "sections ", "show ",
            "profile apply ", "profile show ", "restore", "reset", "overrides",
            "set ", "cap ", "tempstate ", "decrypt"
    };

    private WebView web;
    private final ExecutorService pool = Executors.newFixedThreadPool(3);

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        web = new WebView(this);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(false);
        s.setSupportZoom(false);
        s.setBuiltInZoomControls(false);
        web.setWebViewClient(new WebViewClient());
        web.setBackgroundColor(0xFF0B0E14);
        web.addJavascriptInterface(new Bridge(), "Native");
        setContentView(web);
        web.loadUrl("file:///android_asset/index.html");
    }

    @Override
    public void onBackPressed() {
        if (web != null && web.canGoBack()) web.goBack();
        else super.onBackPressed();
    }

    @Override
    protected void onDestroy() {
        pool.shutdownNow();
        super.onDestroy();
    }

    // ------------------------------------------------------------------ root
    private String runRoot(String cmd) {
        Process p = null;
        try {
            ProcessBuilder pb = new ProcessBuilder("su", "-c", cmd);
            pb.redirectErrorStream(true);
            p = pb.start();
            StringBuilder sb = new StringBuilder();
            BufferedReader br = new BufferedReader(new InputStreamReader(p.getInputStream()));
            String line;
            while ((line = br.readLine()) != null) sb.append(line).append('\n');
            p.waitFor();
            return sb.toString();
        } catch (Exception e) {
            Log.e(TAG, "exec failed", e);
            return "ERR: " + e.getMessage();
        } finally {
            if (p != null) p.destroy();
        }
    }

    /** 校验命令是否在白名单内 */
    private static boolean allowed(String cmd) {
        if (cmd == null) return false;
        if (!cmd.startsWith("mt ")) return false;
        if (cmd.contains(";") || cmd.contains("|") || cmd.contains("&")
                || cmd.contains("`") || cmd.contains("$") || cmd.contains(">")
                || cmd.contains("<") || cmd.contains("\n")) {
            return false;
        }
        String sub = cmd.substring(3);
        for (String a : ALLOWED) {
            if (a.endsWith(" ")) {
                if (sub.startsWith(a)) return true;
            } else if (sub.equals(a)) {
                return true;
            }
        }
        return false;
    }

    private String execChecked(String cmd) {
        if (!allowed(cmd)) return "ERR: 命令不被允许";
        // JS 传的是 "mt json" 这种形式, 换成模块里的绝对路径
        String full = cmd.startsWith("mt ") ? MT + " " + cmd.substring(3) : cmd;
        return runRoot(full);
    }

    static String jsonStr(String s) {
        if (s == null) return "null";
        StringBuilder b = new StringBuilder("\"");
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == '"' || c == '\\') b.append('\\').append(c);
            else if (c == '\n') b.append("\\n");
            else if (c == '\r') b.append("\\r");
            else if (c == '\t') b.append("\\t");
            else if (c < 0x20) b.append(String.format("\\u%04x", (int) c));
            else b.append(c);
        }
        return b.append('"').toString();
    }

    // --------------------------------------------------------------- bridge
    public class Bridge {
        /** 异步执行一条 mt 命令，结果通过 window.__mtDone 回调 */
        @JavascriptInterface
        public void exec(final String cmd, final String cbId) {
            pool.execute(() -> {
                final String out = execChecked(cmd);
                final String js = "window.__mtDone(" + jsonStr(cbId) + "," + jsonStr(out) + ")";
                web.post(() -> {
                    try {
                        web.evaluateJavascript(js, null);
                    } catch (Exception ignored) {
                    }
                });
            });
        }

        /** 检查 root 与模块是否就绪 */
        @JavascriptInterface
        public void check(final String cbId) {
            pool.execute(() -> {
                final StringBuilder sb = new StringBuilder();
                String idOut = runRoot("id -u").trim();
                String modOut = runRoot("ls " + MT + " >/dev/null 2>&1 && echo yes || echo no").trim();
                sb.append("{\"root\":").append(idOut.equals("0"));
                sb.append(",\"module\":\"").append(modOut).append("\"}");
                final String js = "window.__mtDone(" + jsonStr(cbId) + "," + jsonStr(sb.toString()) + ")";
                web.post(() -> {
                    try {
                        web.evaluateJavascript(js, null);
                    } catch (Exception ignored) {
                    }
                });
            });
        }

        @JavascriptInterface
        public void toast(final String msg) {
            runOnUiThread(() -> Toast.makeText(MainActivity.this, msg, Toast.LENGTH_SHORT).show());
        }
    }
}
