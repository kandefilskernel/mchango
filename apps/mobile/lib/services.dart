import 'package:flutter/widgets.dart';

import 'api/api_client.dart';
import 'api/mchango_api.dart';
import 'auth/auth_repository.dart';
import 'storage/key_value_store.dart';

class AppServices {
  AppServices({required this.client, required this.store})
      : api = MchangoApi(client),
        auth = AuthRepository(client, store);

  final ApiClient client;
  final KeyValueStore store;
  final MchangoApi api;
  final AuthRepository auth;
}

/// Donne accès aux services partout dans l'arbre : `Services.of(context)`.
class Services extends InheritedWidget {
  const Services({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Services>()!.services;

  @override
  bool updateShouldNotify(Services oldWidget) => services != oldWidget.services;
}
