// Tests de bout en bout : PostgreSQL et Redis de docker-compose.yml (docker compose up -d).
process.env.NODE_ENV = 'test';
process.env.DATABASE_URL ??= 'postgres://mchango_api:mchango_api_dev@127.0.0.1:5432/mchango';
process.env.REDIS_URL ??= 'redis://127.0.0.1:6379';
process.env.JWT_SECRET ??= 'test-only-secret-test-only-secret-000000';
process.env.OTP_PEPPER ??= 'test-only-pepper-test-only-pepper-000000';
// Toutes les requêtes de test viennent de 127.0.0.1
process.env.OTP_MAX_PER_IP_PER_HOUR = '1000000';
