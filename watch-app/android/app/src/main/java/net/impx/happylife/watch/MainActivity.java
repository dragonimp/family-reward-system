package net.impx.happylife.watch;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.net.ConnectivityManager;
import android.net.NetworkInfo;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.webkit.WebResourceRequest;
import android.webkit.PermissionRequest;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;

public class MainActivity extends Activity {
    private static final int AUDIO_PERMISSION_REQUEST = 41;
    private static final String TRUSTED_WATCH_HOST = "happylife.ai.impx.net";
    private static final String PRIVACY_CONSENT_KEY = "privacy_1_1_accepted";
    private WebView webView;
    private TextView offlineView;
    private PermissionRequest pendingAudioRequest;

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().setStatusBarColor(Color.rgb(22, 100, 58));

        FrameLayout root = new FrameLayout(this);
        webView = new WebView(this);
        offlineView = new TextView(this);
        offlineView.setText("网络不可用");
        offlineView.setTextColor(Color.rgb(23, 35, 27));
        offlineView.setTextSize(16);
        offlineView.setGravity(android.view.Gravity.CENTER);
        offlineView.setVisibility(View.GONE);

        root.addView(webView, new FrameLayout.LayoutParams(-1, -1));
        root.addView(offlineView, new FrameLayout.LayoutParams(-1, -1));
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.addView(root, new LinearLayout.LayoutParams(-1, 0, 1));
        TextView privacyLink = new TextView(this);
        privacyLink.setText("隐私政策");
        privacyLink.setTextColor(Color.rgb(22, 100, 58));
        privacyLink.setTextSize(12);
        privacyLink.setGravity(android.view.Gravity.CENTER);
        privacyLink.setOnClickListener(view -> showPrivacyPolicy(false));
        layout.addView(privacyLink, new LinearLayout.LayoutParams(-1, 32));
        setContentView(layout);

        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setCacheMode(WebSettings.LOAD_DEFAULT);
        settings.setLoadWithOverviewMode(true);
        settings.setUseWideViewPort(false);
        settings.setTextZoom(100);
        settings.setUserAgentString(settings.getUserAgentString()
            + " HappyLifeWatch/" + BuildConfig.VERSION_NAME
            + " (" + Build.MANUFACTURER + " " + Build.MODEL + ")");
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        }

        webView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                view.loadUrl(request.getUrl().toString());
                return true;
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                offlineView.setVisibility(View.GONE);
                webView.setVisibility(View.VISIBLE);
            }
        });
        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onPermissionRequest(PermissionRequest request) {
                runOnUiThread(() -> handleWebPermissionRequest(request));
            }
        });

        if (getPreferences(MODE_PRIVATE).getBoolean(PRIVACY_CONSENT_KEY, false)) {
            loadWatchEntry();
        } else {
            showPrivacyPolicy(true);
        }
    }

    private void showPrivacyPolicy(boolean firstRun) {
        WebView policy = new WebView(this);
        AlertDialog.Builder dialog = new AlertDialog.Builder(this)
            .setTitle("Linko Moment 隐私政策")
            .setView(policy);
        if (firstRun) {
            dialog.setCancelable(false)
                .setPositiveButton("同意并继续", (d, which) -> {
                    getPreferences(MODE_PRIVATE).edit().putBoolean(PRIVACY_CONSENT_KEY, true).apply();
                    loadWatchEntry();
                })
                .setNegativeButton("拒绝", (d, which) -> finish());
        } else {
            dialog.setPositiveButton("关闭", (d, which) -> d.dismiss());
        }
        AlertDialog shown = dialog.show();
        if (firstRun) shown.getButton(AlertDialog.BUTTON_POSITIVE).setEnabled(false);
        policy.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageFinished(WebView view, String url) {
                if (firstRun && "file:///android_asset/privacy.html".equals(url)) {
                    shown.getButton(AlertDialog.BUTTON_POSITIVE).setEnabled(true);
                }
            }
        });
        policy.loadUrl("file:///android_asset/privacy.html");
    }

    private void handleWebPermissionRequest(PermissionRequest request) {
        boolean requestsAudio = false;
        for (String resource : request.getResources()) {
            if (PermissionRequest.RESOURCE_AUDIO_CAPTURE.equals(resource)) {
                requestsAudio = true;
                break;
            }
        }
        if (!requestsAudio || !TRUSTED_WATCH_HOST.equalsIgnoreCase(request.getOrigin().getHost())) {
            request.deny();
            return;
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M
                || checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            request.grant(new String[] { PermissionRequest.RESOURCE_AUDIO_CAPTURE });
            return;
        }
        pendingAudioRequest = request;
        requestPermissions(new String[] { Manifest.permission.RECORD_AUDIO }, AUDIO_PERMISSION_REQUEST);
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode != AUDIO_PERMISSION_REQUEST || pendingAudioRequest == null) return;
        if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            pendingAudioRequest.grant(new String[] { PermissionRequest.RESOURCE_AUDIO_CAPTURE });
        } else {
            pendingAudioRequest.deny();
        }
        pendingAudioRequest = null;
    }

    private void loadWatchEntry() {
        if (!isNetworkAvailable()) {
            webView.setVisibility(View.GONE);
            offlineView.setVisibility(View.VISIBLE);
            return;
        }
        webView.loadUrl(BuildConfig.WATCH_START_URL);
    }

    @SuppressWarnings("deprecation")
    private boolean isNetworkAvailable() {
        ConnectivityManager manager = (ConnectivityManager) getSystemService(CONNECTIVITY_SERVICE);
        if (manager == null) {
            return true;
        }
        NetworkInfo activeNetwork = manager.getActiveNetworkInfo();
        return activeNetwork != null && activeNetwork.isConnected();
    }

    @Override
    public void onBackPressed() {
        if (webView != null && webView.canGoBack()) {
            webView.goBack();
            return;
        }
        super.onBackPressed();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (webView != null) {
            webView.onResume();
        }
    }

    @Override
    protected void onPause() {
        if (webView != null) {
            webView.onPause();
        }
        super.onPause();
    }

    @Override
    protected void onDestroy() {
        if (webView != null) {
            webView.destroy();
        }
        super.onDestroy();
    }
}
