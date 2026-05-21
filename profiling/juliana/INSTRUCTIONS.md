# Micro-optimizations — Juliana Ferreira

## Setup requerido
- Android Studio con emulador **Pixel 6, API 33 (Tiramisu)**
- Flutter SDK en PATH
- Rama: trabajar sobre `SergioCastano` (ya tiene el código base con las optimizaciones de Sergio)

## Tu objetivo
Implementar **2 micro-optimizaciones** en `new_expense_screen.dart` y `set_goal_screen.dart`, y documentar el impacto con profiling BEFORE/AFTER.

---

## Optimizaciones a implementar

### Opt 1 — `const` constructors en `new_expense_screen.dart`

**Problema:** Hay 30+ objetos `BorderRadius`, `EdgeInsets`, y `BoxDecoration` creados sin `const`
dentro de métodos `build()`. Se allocan nuevos objetos en heap en cada rebuild.  
**Fix:** Agregar `const` donde los valores son fijos.  
**Archivo:** `lib/src/screens/new_expense_screen.dart`

Ejecuta este grep para ver los casos:
```bash
grep -n "BorderRadius\.\|EdgeInsets\." lib/src/screens/new_expense_screen.dart | grep -v "const "
```

Patrón a corregir — ejemplo:
```dart
// ANTES (alloca nuevo objeto cada rebuild)
borderRadius: BorderRadius.circular(24),
padding: EdgeInsets.all(14),

// DESPUÉS (cero allocaciones, objeto constante compartido)
borderRadius: const BorderRadius.all(Radius.circular(24)),
padding: const EdgeInsets.all(14),
```

> **Regla:** Solo agrega `const` si TODOS los valores son literales numéricos fijos
> (no variables, no parámetros). Si el valor viene de una variable, NO pongas `const`.

---

### Opt 2 — `ListView` → `ListView.builder` en `set_goal_screen.dart`

**Problema:** `ListView(children: [...])` construye todos los goals en memoria a la vez.  
**Fix:** Convertir a `ListView.builder`.  
**Archivo:** `lib/src/screens/set_goal_screen.dart` línea ~884

Busca este patrón:
```dart
ListView(
  children: [ ... ],
)
```

Convierte a:
```dart
// 1. Extrae los items a una lista antes del return
final items = <Widget>[ ... ]; // mismo contenido

// 2. Reemplaza ListView
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) => items[index],
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

**Screenshot emulador — navegar a New Expense screen:**
```powershell
adb shell screencap -p /sdcard/screen.png
adb pull /sdcard/screen.png "profiling\juliana\BEFORE_new_expense_screen.png"
```

**Reset y captura gfxinfo** — abre y cierra New Expense screen 5 veces seguidas, luego:
```powershell
$pkg = "com.example.spendant_flutter"
adb shell dumpsys gfxinfo $pkg reset
# ... abre/cierra new expense screen 5 veces en el emulador ...
adb shell dumpsys gfxinfo $pkg | Out-File "profiling\juliana\BEFORE_gfxinfo_expense.txt"
adb shell dumpsys meminfo $pkg | Out-File "profiling\juliana\BEFORE_meminfo.txt"
```

**DevTools Performance:**
1. Abre `http://127.0.0.1:<PORT>/devtools/...` en Chrome
2. Tab **Performance** → **Record** → abre/cierra New Expense screen varias veces → **Stop**
3. Screenshot → guardar como `profiling\juliana\BEFORE_devtools_performance.png`

**DevTools Memory:**
1. Tab **Memory** → navega ~15s → click **GC** (ícono basura)
2. Click **CSV** → guardar como `profiling\juliana\BEFORE_memory_allocation.csv`
3. Screenshot → guardar como `profiling\juliana\BEFORE_devtools_memory.png`

> En el CSV busca clases de `new_expense_screen.dart` — fíjate en columna **New Space Instances**.
> Esas son las que se están re-creando en cada rebuild.

---

## Implementar las optimizaciones

Hacer **un commit por optimización**:
```bash
git add lib/src/screens/new_expense_screen.dart
git commit -m "perf: add const constructors to style objects in new_expense_screen"

git add lib/src/screens/set_goal_screen.dart
git commit -m "perf: replace ListView with ListView.builder in set_goal_screen"
```

Verificar que no hay errores después de cada cambio:
```bash
flutter analyze lib/src/screens/new_expense_screen.dart
flutter analyze lib/src/screens/set_goal_screen.dart
```

---

## Flujo de profiling (DESPUÉS del código)

Repetir exactamente los mismos pasos con prefijo `AFTER_`:
```powershell
adb shell dumpsys gfxinfo $pkg reset
# mismo escenario (abre/cierra new expense 5 veces)
adb shell dumpsys gfxinfo $pkg | Out-File "profiling\juliana\AFTER_gfxinfo_expense.txt"
adb shell dumpsys meminfo $pkg | Out-File "profiling\juliana\AFTER_meminfo.txt"
adb shell screencap -p /sdcard/screen.png
adb pull /sdcard/screen.png "profiling\juliana\AFTER_new_expense_screen.png"
```
+ screenshots DevTools Performance y Memory con prefijo `AFTER_`.

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

Del CSV Memory — comparar columna **New Space Instances** de clases de `new_expense_screen.dart`:
- Menos New Space instances = menos allocaciones por rebuild = optimización exitosa.

> **Nota Flutter + gfxinfo:** Si el archivo muestra 0-2 frames, es comportamiento normal — Flutter
> bypasses HWUI. En ese caso usar DevTools Performance tab como fuente principal.

---

## Archivos esperados al final

```
profiling/juliana/
  BEFORE_new_expense_screen.png
  BEFORE_gfxinfo_expense.txt
  BEFORE_meminfo.txt
  BEFORE_devtools_performance.png
  BEFORE_memory_allocation.csv
  BEFORE_devtools_memory.png
  AFTER_new_expense_screen.png
  AFTER_gfxinfo_expense.txt
  AFTER_meminfo.txt
  AFTER_devtools_performance.png
  AFTER_memory_allocation.csv
  AFTER_devtools_memory.png
```
