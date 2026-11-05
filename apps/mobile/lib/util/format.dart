import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';

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

String formatDateTime(DateTime time) => DateFormat('dd/MM/yyyy HH:mm').format(time.toLocal());

// Libellés en getters : ils suivent la langue choisie
Map<String, String> get frequencyLabels => {
  'daily': t('Chaque jour'),
  'weekly': t('Chaque semaine'),
  'monthly': t('Chaque mois'),
};

/// Raisons du score de risque d'une déclaration (codes de l'API, apps/api/src/contributions/risk.ts).
Map<String, String> get riskReasonLabels => {
  'tx_reused_after_rejection': t('Cet ID de transaction a déjà été présenté puis rejeté.'),
  'tx_date_mismatch': t("La date inscrite dans l'ID ne correspond pas au jour du paiement."),
  'sms_amount_mismatch': t('Le SMS du payeur ne montre pas le montant de la cotisation.'),
  'payer_rejected_before': t('Ce membre a eu des paiements rejetés récemment.'),
  'payer_disputed_before': t('Des paiements de ce membre ont été contestés récemment.'),
  'burst': t('Plusieurs déclarations en quelques minutes.'),
  'sms_format_unknown': t("Le SMS du payeur n'a pas la forme habituelle de l'opérateur."),
  'sms_not_pasted': t("ID tapé à la main, sans le SMS de l'opérateur."),
  'first_payment': t('Premier paiement de ce membre dans cette tontine.'),
  'late_declaration': t("Déclaré longtemps après l'échéance."),
};

Map<String, String> get methodLabels => {
  'mpesa': 'M-Pesa',
  'airtel': 'Airtel Money',
  'orange': 'Orange Money',
  'cash': t('Espèces'),
  'other': t('Autre'),
};

Map<String, String> get groupStatusLabels => {
  'draft': t('En préparation'),
  'active': t('En cours'),
  'suspended': t('Suspendu'),
  'closed': t('Terminé'),
};

Map<String, String> get cycleStatusLabels => {
  'upcoming': t('À venir'),
  'open': t('En cours'),
  'completed': t('Terminé'),
  'cancelled': t('Annulé'),
};

/// Statut d'une cotisation : libellé, couleur, icône (lisible même sans savoir lire).
class StatusStyle {
  const StatusStyle(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;
}

Map<String, StatusStyle> get contributionStatusStyles => {
  'expected': StatusStyle(t('Attendue'), Colors.blueGrey, Icons.hourglass_empty),
  'late': StatusStyle(t('En retard'), Colors.deepOrange, Icons.warning_amber_rounded),
  'declared': StatusStyle(t('À confirmer'), Colors.amber, Icons.pending_outlined),
  'disputed': StatusStyle(t('Contestée'), Colors.red, Icons.report_gmailerrorred),
  'confirmed': StatusStyle(t('Confirmée'), Colors.green, Icons.check_circle),
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
