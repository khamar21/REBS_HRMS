// Dashboard widget tests.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rebs_hrms/core/theme.dart';
import 'package:rebs_hrms/domain/records.dart';
import 'package:rebs_hrms/presentation/providers.dart';
import 'package:rebs_hrms/presentation/screens/home_screen.dart';

class LoadingDashboardNotifier extends DashboardNotifier {
  @override
  Future<DashboardData> build() => Completer<DashboardData>().future;
}

void main() {
  testWidgets('dashboard shows loading state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardProvider.overrideWith(LoadingDashboardNotifier.new),
        ],
        child: MaterialApp(theme: buildTheme(), home: const HomeScreen()),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
