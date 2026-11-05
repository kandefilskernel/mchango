-- ============================================================
-- Semaine 4 : rappels avant échéance (un canal : SMS ; un rappel par membre et par tour)
-- ============================================================

-- Clé d'unicité métier d'une notification, ex. « reminder:<cycle>:<membre> ».
-- L'insertion avant envoi garantit un seul SMS, même avec plusieurs serveurs en parallèle.
ALTER TABLE notifications
    ADD COLUMN dedupe_key TEXT UNIQUE,
    ADD COLUMN error TEXT;

CREATE INDEX idx_notifications_status ON notifications (status, created_at);
