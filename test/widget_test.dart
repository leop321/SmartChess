import 'package:en_passant/model/app_model.dart';
import 'package:en_passant/model/user_preferences.dart';
import 'package:en_passant/views/tactics_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('TacticsView renders placeholder without errors',
      (WidgetTester tester) async {
    final prefs = UserPreferences();
    final appModel = AppModel(prefs: prefs);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppModel>.value(
        value: appModel,
        child: const MaterialApp(
          home: TacticsView(),
        ),
      ),
    );

    expect(find.text('DEMNÄCHST VERFÜGBAR'), findsOneWidget);
    expect(find.text('Taktikaufgaben in Überarbeitung'), findsOneWidget);

    appModel.dispose();
    await tester.pump();
  });
}
