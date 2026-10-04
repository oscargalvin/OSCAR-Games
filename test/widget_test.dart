import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oscar_games/main.dart';
import 'package:oscar_games/services/save_service.dart';

void main() {
  testWidgets('App launches and shows home screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await SaveService.instance.init();
    await tester.pumpWidget(const OscarGamesApp());
    expect(find.text("Oscar Galvin's"), findsOneWidget);
    expect(find.text('Game Center'), findsOneWidget);
  });
}
