"""Construit spec/test-vectors/audit_chain.json à partir de la sortie de vectors_source.sql.

1. Recalcule chaque hash avec une implémentation Python indépendante : si elle diverge
   de PostgreSQL, le script s'arrête (la spécification serait ambiguë).
2. Ajoute des cas de falsification, avec le premier seq invalide attendu.

Usage : python -I make_vectors.py <sortie_postgres.json> <audit_chain.json>
"""
import copy
import hashlib
import json
import sys

GENESIS = "0" * 64


def audit_hash(e):
    fields = [
        "mchango-v1",
        e["chain_id"],
        str(e["seq"]),
        e["prev_hash"],
        e["actor_type"],
        e["actor_id"] or "",
        e["device_id"] or "",
        e["action"],
        e["created_at"],
        e["payload"],
        e["signature"] or "",
    ]
    return hashlib.sha256("\n".join(fields).encode("utf-8")).hexdigest()


def first_invalid_seq(events):
    prev, expected = GENESIS, 1
    for e in events:
        if e["seq"] != expected or e["prev_hash"] != prev or e["hash"] != audit_hash(e):
            return expected
        prev, expected = e["hash"], expected + 1
    return None


def main(src, dst):
    with open(src, encoding="utf-8") as f:
        data = json.load(f)

    for chain in data["chains"]:
        for e in chain["events"]:
            if audit_hash(e) != e["hash"]:
                sys.exit(f"Divergence Python/PostgreSQL : {chain['chain_id']} seq {e['seq']}")
        assert first_invalid_seq(chain["events"]) is None

    group = next(c for c in data["chains"] if c["chain_id"].startswith("group:"))
    base = group["events"]
    assert len(base) >= 4, "il faut au moins 4 événements dans la chaîne du groupe"

    def case(description, expected, mutate):
        events = copy.deepcopy(base)
        mutate(events)
        got = first_invalid_seq(events)
        if got != expected:
            sys.exit(f"Cas « {description} » : attendu {expected}, obtenu {got}")
        return {"description": description, "chain_id": group["chain_id"],
                "events": events, "first_invalid_seq": expected}

    def alter_payload(events):
        events[1]["payload"] = events[1]["payload"].replace("20000", "2000")

    def delete_event(events):
        del events[2]

    def swap_events(events):
        events[1], events[2] = events[2], events[1]

    def rehash_altered(events):
        # Falsificateur malin : il recalcule le hash de l'événement modifié,
        # mais ne peut pas réécrire le reste sans que prev_hash du suivant casse.
        events[1]["payload"] = events[1]["payload"].replace("20000", "2000")
        events[1]["hash"] = audit_hash(events[1])

    def change_actor(events):
        events[2]["actor_id"] = "11111111-1111-4111-8111-111111111111"

    def change_timestamp(events):
        events[3]["created_at"] = events[3]["created_at"][:-5] + "999Z"

    def reformat_payload(events):
        # Même JSON, autre écriture : doit être rejeté (le payload est haché tel quel)
        events[0]["payload"] = json.dumps(json.loads(events[0]["payload"]), indent=None,
                                          separators=(",", ":"))

    data["invalid_cases"] = [
        case("montant modifié dans le payload", 2, alter_payload),
        case("événement supprimé (trou dans seq)", 3, delete_event),
        case("deux événements inversés", 2, swap_events),
        case("payload modifié et son hash recalculé", 3, rehash_altered),
        case("auteur changé", 3, change_actor),
        case("horodatage changé", 4, change_timestamp),
        case("payload re-sérialisé (même JSON, autres octets)", 1, reformat_payload),
    ]

    with open(dst, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    n = sum(len(c["events"]) for c in data["chains"])
    print(f"{n} événements valides, {len(data['invalid_cases'])} cas de falsification -> {dst}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
