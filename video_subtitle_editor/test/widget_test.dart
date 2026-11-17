import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:video_subtitle_editor/app.dart';
import 'package:video_subtitle_editor/state/app_state.dart';

void main() {
  testWidgets('App boots to Home', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('工程管理'), findsOneWidget);
  });
}
