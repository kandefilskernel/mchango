-- ============================================================
-- Semaine 3 : numéro de reçu unique, attribué quand la cotisation est confirmée.
-- Affiché sous la forme MCH-00000042.
-- ============================================================

CREATE SEQUENCE receipt_number_seq;

ALTER TABLE contributions
    ADD COLUMN receipt_number BIGINT UNIQUE,
    ADD CONSTRAINT contributions_receipt_only_when_confirmed
        CHECK (receipt_number IS NULL OR status = 'confirmed');

GRANT USAGE ON SEQUENCE receipt_number_seq TO mchango_app;
