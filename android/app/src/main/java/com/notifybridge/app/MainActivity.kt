package com.notifybridge.app

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings as AndroidSettings
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.app.NotificationManagerCompat
import androidx.core.graphics.drawable.toBitmap
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        Sender.start(applicationContext)
        setContent { NbTheme { Surface(color = MaterialTheme.colorScheme.background) { Root() } } }
    }

    @Composable
    private fun Root() {
        var apps by remember { mutableStateOf(false) }
        BackHandler(enabled = apps) { apps = false }
        if (apps) AppsScreen(onBack = { apps = false }) else HomeScreen(onApps = { apps = true })
    }

    // ───────────────────────── Home ─────────────────────────

    @Composable
    private fun HomeScreen(onApps: () -> Unit) {
        val ctx = LocalContext.current
        var key by remember { mutableStateOf(Settings.key(ctx)) }
        var access by remember { mutableStateOf(hasAccess()) }
        var battery by remember { mutableStateOf(batteryOk()) }
        var status by remember { mutableStateOf(Settings.status(ctx)) }
        var advanced by remember { mutableStateOf(false) }
        var link by remember { mutableStateOf(Settings.link(ctx)) }
        var queued by remember { mutableStateOf(Settings.queued(ctx)) }
        val perm = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {}
        var skipScreenOn by remember { mutableStateOf(Settings.skipWhenScreenOn(ctx)) }
        var clipFromMac by remember { mutableStateOf(Settings.clipFromMac(ctx)) }

        LaunchedEffect(Unit) {
            runCatching { perm.launch(arrayOf("android.permission.ACCESS_LOCAL_NETWORK", "android.permission.POST_NOTIFICATIONS")) }
        }

        val lifecycle = LocalLifecycleOwner.current.lifecycle
        DisposableEffect(lifecycle) {
            val obs = LifecycleEventObserver { _, e ->
                if (e == Lifecycle.Event.ON_RESUME) {
                    access = hasAccess(); battery = batteryOk(); status = Settings.status(ctx)
                }
            }
            lifecycle.addObserver(obs)
            onDispose { lifecycle.removeObserver(obs) }
        }

        DisposableEffect(Unit) {
            val prefs = ctx.getSharedPreferences("nb", android.content.Context.MODE_PRIVATE)
            val listener = android.content.SharedPreferences.OnSharedPreferenceChangeListener { _, k ->
                if (k == "status") status = Settings.status(ctx)
                if (k == "link") link = Settings.link(ctx)
                if (k == "queued") queued = Settings.queued(ctx)
            }
            prefs.registerOnSharedPreferenceChangeListener(listener)
            onDispose { prefs.unregisterOnSharedPreferenceChangeListener(listener) }
        }

        val paired = key.length == 44
        val done = listOf(access, battery, paired).count { it }
        val ready = access && paired

        Column(
            Modifier.fillMaxSize().safeDrawingPadding().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Hero(ready = ready, remaining = 3 - done, status = status, link = link, queued = queued)

            SectionCard(title = getString(R.string.setup_title)) {
                StepRow(
                    done = access, number = 1,
                    title = getString(R.string.step_access_title),
                    subtitle = if (access) getString(R.string.step_access_done) else getString(R.string.step_access_todo),
                    action = getString(R.string.action_open),
                ) { startActivity(Intent(AndroidSettings.ACTION_NOTIFICATION_LISTENER_SETTINGS)) }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                StepRow(
                    done = battery, number = 2,
                    title = getString(R.string.step_battery_title),
                    subtitle = if (battery) getString(R.string.step_battery_done) else getString(R.string.step_battery_todo),
                    action = getString(R.string.action_remove),
                ) {
                    runCatching {
                        startActivity(Intent(AndroidSettings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")))
                    }
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                StepRow(
                    done = paired, number = 3,
                    title = getString(R.string.step_pair_title),
                    subtitle = if (paired) getString(R.string.step_pair_done) else getString(R.string.step_pair_todo),
                    action = if (paired) getString(R.string.action_renew) else getString(R.string.action_scan),
                    actionAlways = true,
                ) {
                    GmsBarcodeScanning.getClient(
                        ctx,
                        GmsBarcodeScannerOptions.Builder()
                            .setBarcodeFormats(com.google.mlkit.vision.barcode.common.Barcode.FORMAT_QR_CODE)
                            .build(),
                    ).startScan()
                        .addOnSuccessListener { b ->
                            val k = Uri.parse(b.rawValue ?: "").getQueryParameter("key")
                            if (k != null && k.length == 44) {
                                key = k; Settings.setKey(ctx, k); status = getString(R.string.status_paired_ok)
                            } else status = getString(R.string.status_invalid_qr)
                        }
                        .addOnFailureListener { status = getString(R.string.status_qr_failed, it.message ?: "") }
                }
            }

            SectionCard(title = getString(R.string.settings_title)) {
                NavRow(getString(R.string.nav_apps_title), getString(R.string.nav_apps_sub), onClick = onApps)
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                NavRow(getString(R.string.nav_test_title), getString(R.string.nav_test_sub)) {
                    Sender.send(ctx, "AndPear", getString(R.string.test_title), getString(R.string.test_body))
                    status = getString(R.string.status_sending)
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                SwitchRow(
                    getString(R.string.switch_screen_title), getString(R.string.switch_screen_sub),
                    skipScreenOn,
                ) { skipScreenOn = it; Settings.setSkipWhenScreenOn(ctx, it) }
            }

            SectionCard(title = getString(R.string.section_clipboard)) {
                NavRow(getString(R.string.clip_send_title), getString(R.string.clip_send_sub)) {
                    val cm = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
                    val t = cm.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(ctx)?.toString()
                    if (t.isNullOrBlank()) status = getString(R.string.status_clip_empty)
                    else { Sender.sendClip(ctx, t); status = getString(R.string.status_sending) }
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                SwitchRow(
                    getString(R.string.clip_recv_title), getString(R.string.clip_recv_sub),
                    clipFromMac,
                ) { clipFromMac = it; Settings.setClipFromMac(ctx, it) }
                Text(
                    getString(R.string.clip_tip),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                )
            }

            SectionCard(title = getString(R.string.section_advanced)) {
                NavRow(
                    if (advanced) getString(R.string.key_hide) else getString(R.string.key_enter),
                    getString(R.string.key_sub),
                ) { advanced = !advanced }
                if (advanced) {
                    OutlinedTextField(
                        value = key,
                        onValueChange = { key = it.trim(); Settings.setKey(ctx, it) },
                        label = { Text(getString(R.string.key_label)) },
                        singleLine = true,
                        shape = RoundedCornerShape(14.dp),
                        modifier = Modifier.fillMaxWidth().padding(16.dp),
                    )
                }
            }

            Text(
                getString(R.string.privacy_note),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
            )
        }
    }

    @Composable
    private fun Hero(ready: Boolean, remaining: Int, status: String, link: String, queued: Int) {
        Column(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(28.dp)).background(Brand.Gradient).padding(22.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text("AndPear", color = androidx.compose.ui.graphics.Color.White.copy(alpha = 0.85f), fontSize = 14.sp, fontWeight = FontWeight.Medium)
            Text(
                if (ready) getString(R.string.hero_ready) else getString(R.string.hero_setup_needed),
                color = androidx.compose.ui.graphics.Color.White, fontSize = 34.sp, fontWeight = FontWeight.Bold,
            )
            Text(
                when {
                    !ready -> getString(R.string.steps_left, remaining)
                    link == "connected" -> getString(R.string.link_connected)
                    link == "nowifi" -> getString(R.string.link_nowifi)
                    else -> getString(R.string.link_searching)
                },
                color = androidx.compose.ui.graphics.Color.White.copy(alpha = 0.95f), fontSize = 15.sp,
            )
            Spacer(Modifier.height(8.dp))
            Box(
                Modifier.clip(RoundedCornerShape(50)).background(androidx.compose.ui.graphics.Color.White.copy(alpha = 0.22f))
                    .padding(horizontal = 12.dp, vertical = 6.dp),
            ) {
                Text(status, color = androidx.compose.ui.graphics.Color.White, fontSize = 13.sp)
            }
            if (queued > 0) {
                Box(
                    Modifier.clip(RoundedCornerShape(50)).background(androidx.compose.ui.graphics.Color.White.copy(alpha = 0.32f))
                        .padding(horizontal = 12.dp, vertical = 6.dp),
                ) {
                    Text(getString(R.string.queued_waiting, queued), color = androidx.compose.ui.graphics.Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }

    @Composable
    private fun SectionCard(title: String, content: @Composable ColumnScope.() -> Unit) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                title.uppercase(),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(start = 8.dp),
            )
            Card(
                shape = RoundedCornerShape(22.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
                modifier = Modifier.fillMaxWidth(),
            ) { Column(content = content) }
        }
    }

    @Composable
    private fun StepRow(
        done: Boolean, number: Int, title: String, subtitle: String, action: String,
        actionAlways: Boolean = false, onAction: () -> Unit,
    ) {
        Row(
            Modifier.fillMaxWidth().padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Box(
                Modifier.size(36.dp).clip(CircleShape)
                    .background(if (done) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    if (done) "✓" else "$number",
                    color = if (done) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant,
                    fontWeight = FontWeight.Bold, fontSize = 16.sp,
                )
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (!done || actionAlways) {
                if (done) TextButton(onClick = onAction) { Text(action) }
                else Button(onClick = onAction, shape = RoundedCornerShape(12.dp), contentPadding = PaddingValues(horizontal = 16.dp)) { Text(action) }
            }
        }
    }

    @Composable
    private fun SwitchRow(title: String, subtitle: String, checked: Boolean, onChange: (Boolean) -> Unit) {
        Row(
            Modifier.fillMaxWidth().clickable { onChange(!checked) }.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Switch(checked = checked, onCheckedChange = onChange)
        }
    }

    @Composable
    private fun NavRow(title: String, subtitle: String, onClick: () -> Unit) {
        Row(
            Modifier.fillMaxWidth().clickable(onClick = onClick).padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text("›", fontSize = 26.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }

    // ───────────────────────── Apps ─────────────────────────

    @Composable
    private fun AppsScreen(onBack: () -> Unit) {
        val ctx = LocalContext.current
        var list by remember { mutableStateOf<List<Pair<String, String>>?>(null) }
        var off by remember { mutableStateOf(Settings.disabled(ctx)) }
        var query by remember { mutableStateOf("") }

        LaunchedEffect(Unit) {
            list = withContext(Dispatchers.IO) {
                val pm = packageManager
                val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                pm.queryIntentActivities(intent, PackageManager.MATCH_ALL)
                    .map { it.activityInfo.packageName to it.loadLabel(pm).toString() }
                    .filter { it.first != packageName }
                    .distinctBy { it.first }
                    .sortedBy { it.second.lowercase() }
            }
        }

        Column(Modifier.fillMaxSize().safeDrawingPadding()) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextButton(onClick = onBack) { Text("‹", fontSize = 30.sp) }
                Column {
                    Text(getString(R.string.nav_apps_title), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    val total = list?.size ?: 0
                    if (total > 0) {
                        val on = list!!.count { it.first !in off }
                        Text(getString(R.string.apps_on, on, total), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            OutlinedTextField(
                value = query, onValueChange = { query = it }, singleLine = true,
                placeholder = { Text(getString(R.string.apps_search)) },
                shape = RoundedCornerShape(16.dp),
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            )
            Spacer(Modifier.height(8.dp))
            val items = list
            if (items == null) {
                Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            } else {
                Card(
                    shape = RoundedCornerShape(22.dp),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    modifier = Modifier.fillMaxSize().padding(start = 16.dp, end = 16.dp, bottom = 12.dp),
                ) {
                    LazyColumn(Modifier.fillMaxSize()) {
                        items(items.filter { it.second.contains(query, ignoreCase = true) }, key = { it.first }) { (pkg, label) ->
                            Row(
                                Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(14.dp),
                            ) {
                                AppIcon(pkg)
                                Text(label, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                                Switch(checked = pkg !in off, onCheckedChange = {
                                    Settings.setEnabled(ctx, pkg, it)
                                    off = Settings.disabled(ctx)
                                })
                            }
                        }
                    }
                }
            }
        }
    }

    @Composable
    private fun AppIcon(pkg: String) {
        val icon by produceState<androidx.compose.ui.graphics.ImageBitmap?>(null, pkg) {
            value = withContext(Dispatchers.IO) {
                runCatching { packageManager.getApplicationIcon(pkg).toBitmap(96, 96).asImageBitmap() }.getOrNull()
            }
        }
        val shape = RoundedCornerShape(11.dp)
        val m = Modifier.size(42.dp).clip(shape)
        if (icon != null) Image(icon!!, contentDescription = null, modifier = m)
        else Box(m.background(MaterialTheme.colorScheme.surfaceVariant))
    }

    private fun hasAccess() = NotificationManagerCompat.getEnabledListenerPackages(this).contains(packageName)

    private fun batteryOk() =
        (getSystemService(POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(packageName)
}
