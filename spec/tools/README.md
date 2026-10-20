# Régénérer les vecteurs de test

À refaire uniquement si le format du hash ou `db/001_schema.sql` change. Docker Desktop, PowerShell, depuis la racine du dépôt :

```powershell
docker run -d --name mchango-pg-vec -e POSTGRES_PASSWORD=dev -e POSTGRES_DB=mchango -v "${PWD}:/repo:ro" postgres:16
```

```powershell
docker exec mchango-pg-vec psql -U postgres -d mchango -v ON_ERROR_STOP=1 -q -f /repo/db/001_schema.sql -f /repo/db/002_roles.sql
```

```powershell
docker exec mchango-pg-vec psql -U postgres -d mchango -q -f /repo/spec/tools/vectors_source.sql | Out-File -Encoding utf8 pg_vectors.json
```

```powershell
python -I spec/tools/make_vectors.py pg_vectors.json spec/test-vectors/audit_chain.json
```

```powershell
docker rm -f mchango-pg-vec; Remove-Item pg_vectors.json
```

`make_vectors.py` recalcule chaque hash en Python et s'arrête si le résultat diffère de PostgreSQL. Il ajoute ensuite les cas de falsification. Relancer ensuite `dart test` dans `packages/mchango_audit`.
