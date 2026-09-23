CREATE USER postgres_exporter
WITH
    PASSWORD 'exporter_secure_password';

GRANT CONNECT ON DATABASE traccar TO postgres_exporter;

GRANT pg_monitor TO postgres_exporter;