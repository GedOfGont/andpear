package com.notifybridge.app

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

/** Brand colours taken from the app icon: teal fading to green. */
object Brand {
    val Teal = Color(0xFF3AB0B8)
    val Green = Color(0xFF3FC48E)
    val Gradient = Brush.linearGradient(listOf(Teal, Green))
}

private val Light = lightColorScheme(
    primary = Color(0xFF16897F),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFD5F2EC),
    onPrimaryContainer = Color(0xFF00382F),
    background = Color(0xFFF3F7F7),
    surface = Color.White,
    onSurface = Color(0xFF14201F),
    surfaceVariant = Color(0xFFE4ECEB),
    onSurfaceVariant = Color(0xFF55696A),
    outlineVariant = Color(0xFFD3DEDD),
)

private val Dark = darkColorScheme(
    primary = Color(0xFF55D6C2),
    onPrimary = Color(0xFF00382F),
    primaryContainer = Color(0xFF14463F),
    onPrimaryContainer = Color(0xFFBFF3E9),
    background = Color(0xFF0E1514),
    surface = Color(0xFF172120),
    onSurface = Color(0xFFE1EBEA),
    surfaceVariant = Color(0xFF263231),
    onSurfaceVariant = Color(0xFF9DB1B0),
    outlineVariant = Color(0xFF30403F),
)

@Composable
fun NbTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = if (isSystemInDarkTheme()) Dark else Light, content = content)
}
