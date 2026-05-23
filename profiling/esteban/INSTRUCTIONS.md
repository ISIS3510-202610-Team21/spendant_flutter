# Micro-optimizations — Esteban Castelblanco

## Setup requerido
- Android Studio con emulador **Pixel 6, API 33 (Tiramisu)**
- Flutter SDK en PATH
- Rama: trabajar sobre `SergioCastano` (ya tiene el código base con las optimizaciones de Sergio)

## Tu objetivo
Implementar **2 micro-optimizaciones** en `budget_screen.dart` y documentar el impacto con profiling BEFORE/AFTER.

---

## Optimizaciones a implementar

### Opt 1 — `ListView` → `ListView.builder` en `budget_screen.dart`

**Problema:** `ListView(children: [...])` construye todos los items en memoria a la vez.  
**Fix:** Convertir a `ListView.builder` para construcción lazy (solo items visibles).  
**Archivo:** `lib/src/screens/budget_screen.dart` línea ~124

Busca este patrón:
```dart
return ListView(
  children: [ ... ],
);
```

Convierte a:
```dart
// 1. Construye lista flat de widgets antes del return
final items = <Widget>[ ... ]; // mismo contenido que estaba en children

// 2. Reemplaza ListView
return ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) => items[index],
);
```

---

### Opt 2 — `RepaintBoundary` alrededor del gráfico de budget

**Problema:** El gráfico/chart de presupuesto repinta junto con toda la pantalla cuando cambia cualquier estado.  
**Fix:** Envolver el widget del gráfico con `RepaintBoundary` para aislar su repaint layer.  
**Archivo:** `lib/src/screens/budget_screen.dart`

Busca el widget principal del chart/gráfico y envuélvelo:
```dart
// ANTES
SomeChartWidget(...)

// DESPUÉS
RepaintBoundary(
  child: SomeChartWidget(...),
)
```

---

## Flujo de profiling (ANTES de tocar código)

### 1. Lanzar app en profile mode
```powershell
flutter run --profile -d <emulator-id>
```
Copia el VM Service URL que aparece en consola.

### 2. Capturar métricas BEFORE

**Screenshot del emulador (desde PowerShell):**
```powershell
adb shell screencap -p /sdcard/screen.png
adb pull /sdcard/screen.png "profiling\esteban\BEFORE_budget_screen.png"
```

**Reset y captura gfxinfo** — navega a budget screen, scrollea ~10s, luego:
```powershell
$pkg = "com.example.spendant_flutter"
adb shell dumpsys gfxinfo $pkg reset
# ... scrollea 10 segundos en el emulador ...
adb shell dumpsys gfxinfo $pkg | Out-File "profiling\esteban\BEFORE_gfxinfo_budget.txt"
adb shell dumpsys meminfo $pkg | Out-File "profiling\esteban\BEFORE_meminfo.txt"
```

**DevTools Performance:**
1. Abre `http://127.0.0.1:<PORT>/devtools/...` en Chrome
2. Tab **Performance** → **Record** → scrollea budget screen ~10s → **Stop**
3. Screenshot → guardar como `profiling\esteban\BEFORE_devtools_performance.png`

**DevTools Memory:**
1. Tab **Memory** → navega ~15s → click **GC** (ícono basura)
2. Click **CSV** → guardar como `profiling\esteban\BEFORE_memory_allocation.csv`
3. Screenshot → guardar como `profiling\esteban\BEFORE_devtools_memory.png`

---

## Implementar las optimizaciones

Hacer **un commit por optimización**:
```bash
git add lib/src/screens/budget_screen.dart
git commit -m "perf: replace ListView with ListView.builder in budget_screen"

# luego del segundo cambio:
git commit -m "perf: add RepaintBoundary around budget chart in budget_screen"
```

---

## Flujo de profiling (DESPUÉS del código)

Repetir exactamente los mismos pasos con prefijo `AFTER_`:
```powershell
adb shell dumpsys gfxinfo $pkg reset
# scrollea 10s
adb shell dumpsys gfxinfo $pkg | Out-File "profiling\esteban\AFTER_gfxinfo_budget.txt"
adb shell dumpsys meminfo $pkg | Out-File "profiling\esteban\AFTER_meminfo.txt"
adb shell screencap -p /sdcard/screen.png
adb pull /sdcard/screen.png "profiling\esteban\AFTER_budget_screen.png"
```
+ screenshots de DevTools Performance y Memory con prefijo `AFTER_`.

---

## Métricas a registrar (tabla BEFORE vs AFTER)

Extraer del gfxinfo:
```
Total frames rendered
Janky frames (%)
50th percentile
90th percentile
99th percentile
Number Slow UI thread
Number Slow issue draw commands
```

> **Nota Flutter + gfxinfo:** Si el archivo muestra 0-2 frames, es comportamiento normal — Flutter
> bypasses HWUI. En ese caso usar DevTools Performance tab como fuente principal.

---

## Archivos esperados al final

```
profiling/esteban/
  BEFORE_budget_screen.png
  BEFORE_gfxinfo_budget.txt
  BEFORE_meminfo.txt
  BEFORE_devtools_performance.png
  BEFORE_memory_allocation.csv
  BEFORE_devtools_memory.png
  AFTER_budget_screen.png
  AFTER_gfxinfo_budget.txt
  AFTER_meminfo.txt
  AFTER_devtools_performance.png
  AFTER_memory_allocation.csv
  AFTER_devtools_memory.png
```
