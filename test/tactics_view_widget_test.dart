import 'package:en_passant/model/app_model.dart';
import 'package:en_passant/model/user_preferences.dart';
import 'package:en_passant/views/tactics_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Widget-Tests für TacticsView.
///
/// Hinweis: AppModel enthält Server-Warmup-Timer (periodic).
/// Die Tests müssen addTearDown(appModel.dispose) aufrufen, um alle
/// pending Timers vor dem Framework-Check zu canceln.
void main() {
  testWidgets('TacticsView rendert ohne Exception und zeigt Titel',
      (tester) async {
    final prefs = UserPreferences();
    final appModel = AppModel(prefs: prefs, skipServerWarmup: true);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppModel>.value(value: appModel),
        ],
        child: const MaterialApp(home: TacticsView()),
      ),
    );

    // Initiales Rendering — kein crash, kein Exception
    expect(find.byType(TacticsView), findsOneWidget);
    expect(find.text('TAKTIK'), findsOneWidget);
    expect(find.text('Puzzles & Training'), findsOneWidget);

    await tester.pumpAndSettle();
  });

  testWidgets('TacticsView zeigt Loading-Spinner im initialen Zustand',
      (tester) async {
    final prefs = UserPreferences();
    final appModel = AppModel(prefs: prefs, skipServerWarmup: true);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppModel>.value(value: appModel),
        ],
        child: const MaterialApp(home: TacticsView()),
      ),
    );

    // Direkt nach dem initialen Pump → loading-Zustand
    // CircularProgressIndicator zeigt den Loading-State an
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();
  });

  testWidgets('TacticsView rendert Brett nach Ladevorgang',
      (tester) async {
    final prefs = UserPreferences();
    final appModel = AppModel(prefs: prefs, skipServerWarmup: true);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppModel>.value(value: appModel),
        ],
        child: const MaterialApp(home: TacticsView()),
      ),
    );

    // FakePuzzleRepository lädt synchron (wenn async delay vernachlässigt),
    // nach 150ms Repo-Delay + 500ms Gegnerzug = Brett sichtbar
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();

    // CustomPaint-Widgets sollten vorhanden sein (Board-Painter)
    expect(find.byType(CustomPaint), findsWidgets);

    await tester.pumpAndSettle();
  });
}
