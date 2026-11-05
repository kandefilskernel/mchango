import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'api/api_client.dart';
import 'app.dart';
import 'config.dart';
import 'services.dart';
import 'storage/key_value_store.dart';
import 'l10n/l10n.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  const store = SecureKeyValueStore();
  await Lang.instance.load(store);
  final services = AppServices(client: ApiClient(await resolveApiUrl(store)), store: store);
  await services.auth.load();
  runApp(MchangoApp(services: services));
}
