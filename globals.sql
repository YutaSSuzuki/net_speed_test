--
-- PostgreSQL database cluster dump
--

\restrict SVVwP5OtQya3zI59bfznwArf6kxwBTbgm2ohiMHnC5xyeE9jnbIh8Mi2QpeLlTH

SET default_transaction_read_only = off;

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

--
-- Roles
--

CREATE ROLE netmon;
ALTER ROLE netmon WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS PASSWORD 'SCRAM-SHA-256$4096:JnuSFQRITTAG5GRuv/YvwA==$j6pJoUtqYPzZA/OOmf71FS4Gu/eTPP3PpXlDu0gUu9w=:cg2bXD1tpQRvVts68bpOsacwmVZZ1ZY3BBrBnyg7YpM=';
CREATE ROLE postgres;
ALTER ROLE postgres WITH SUPERUSER INHERIT CREATEROLE CREATEDB LOGIN REPLICATION BYPASSRLS;

--
-- User Configurations
--








\unrestrict SVVwP5OtQya3zI59bfznwArf6kxwBTbgm2ohiMHnC5xyeE9jnbIh8Mi2QpeLlTH

--
-- PostgreSQL database cluster dump complete
--

