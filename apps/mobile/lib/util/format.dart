import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Montant en unités mineures → texte : 20000 CDF → « 20 000 FC », 2050 USD → « 20,50 $ ».
String formatAmount(int minor, String currency) {
  final grouped = NumberFormat.decimalPattern('fr_FR');
  if (currency == 'USD') {
    final units = minor ~/ 100;
    final cents = (minor % 100).toString().padLeft(2, '0');
    return '${_spaces(grouped.format(units))},$cents \$';
  }
  return '${_spaces(grouped.format(minor))} FC';
}

/// Saisie utilisateur (« 20 000 », « 20,50 ») → unités mineures, ou null si invalide.
int? parseAmount(String input, String currency) {
  final clean = input.replaceAll(RegExp(r'[\s  ]'), '').replaceAll(',', '.');
  if (currency == 'USD') {
    final m = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(clean);
    if (m == null) return null;
    return int.parse(m[1]!) * 100 + int.parse((m[2] ?? '0').padRight(2, '0'));
  }
  return RegExp(r'^\d+$').hasMatch(clean) ? int.parse(clean) : null;
}

// L'espace insécable fine de intl s'affiche mal sur certains téléphones : espace simple.
String _spaces(String s) => s.replaceAll(RegExp(r'[  ]'), ' ');

/// « 2026-11-02 » → « 02/11/2026 ».
String formatDate(String isoDate) {
  final p = isoDate.split('-');
  return '${p[2]}/${p[1]}/${p[0]}';
}

String formatDateTime(DateTime t) => DateFormat('dd/MM/yyyy HH:mm').format(t.toLocal());

const frequencyLabels = {
  'daily': 'Chaque jour',
  'weekly': 'Chaque semaine',
  'monthly': 'Chaque mois',
};

const methodLabels = {
  'mpesa': 'M-Pesa',
  'airtel': 'Airtel Money',
  'orange': 'Orange Money',
  'cash': 'Espèces',
  'other': 'Autre',
};

const groupStatusLabels = {
  'draft': 'En préparation',
  'active': 'En cours',
  'suspended': 'Suspendu',
  'closed': 'Terminé',
};

const cycleStatusLabels = {
  'upcoming': 'À venir',
  'open': 'En cours',
  'completed': 'Terminé',
  'cancelled': 'Annulé',
};

/// Statut d'une cotisation : libellé, couleur, icône (lisible même sans savoir lire).
class StatusStyle {
  const StatusStyle(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;
}

const contributionStatusStyles = {
  'expected': StatusStyle('Attendue', Colors.blueGrey, Icons.hourglass_empty),
  'late': StatusStyle('En retard', Colors.deepOrange, Icons.warning_amber_rounded),
  'declared': StatusStyle('À confirmer', Colors.amber, Icons.pending_outlined),
  'disputed': StatusStyle('Contestée', Colors.red, Icons.report_gmailerrorred),
  'confirmed': StatusStyle('Confirmée', Colors.green, Icons.check_circle),
};

/// UUID v4 aléatoire (identifiant hors ligne d'une déclaration).
String uuidV4() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
