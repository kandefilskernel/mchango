export const riskLabels: Record<string, string> = { low: "Risque faible", medium: "À surveiller", high: "Risque élevé" };
export const riskBadge = (r: string) => (r === "high" ? "badge-danger" : r === "medium" ? "badge-warn" : "badge-ok");

export const severityLabels: Record<string, string> = { info: "Info", attention: "Attention", urgent: "Urgent" };
export const severityBadge = (s: string) => (s === "urgent" ? "badge-danger" : s === "attention" ? "badge-warn" : "badge-ok");

export const categoryLabels: Record<string, string> = {
  late_payment: "Retards",
  amount_mismatch: "Montant",
  duplicate_reference: "ID de transaction réutilisé",
  unconfirmed: "Confirmation en attente",
  dispute_pattern: "Litiges",
  collusion_suspicion: "Possible entente",
  feedback_complaint: "Plainte dans un avis",
  other: "Autre",
};

export const ruleLabels: Record<string, string> = {
  duplicate_reference: "ID de transaction réutilisé",
  unconfirmed: "Pas confirmé après 72 h",
  repeated_late: "Retards répétés",
  repeated_disputes: "Contestations répétées",
  rejected: "Déclaration rejetée",
  same_witness: "Toujours le même témoin",
};

export const sentimentLabels: Record<string, string> = { positive: "Plutôt positif", mixed: "Partagé", negative: "Plutôt négatif" };
