--
-- PostgreSQL database dump
--

\restrict SVjHG7Og2PUYM7dUWrS0M0osFhhgtpnUmBMvUqTYufHXdpLdkkZbOdOpjefg7Qs

-- Dumped from database version 16.13 (Ubuntu 16.13-0ubuntu0.24.04.1)
-- Dumped by pg_dump version 16.13 (Ubuntu 16.13-0ubuntu0.24.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: speedtest_logs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.speedtest_logs (
    id integer NOT NULL,
    measured_at timestamp without time zone NOT NULL,
    download_mbps numeric,
    upload_mbps numeric,
    ping_ms numeric,
    link_type text DEFAULT 'wired'::text NOT NULL,
    iface text,
    host text
);


ALTER TABLE public.speedtest_logs OWNER TO postgres;

--
-- Name: speedtest_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.speedtest_logs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.speedtest_logs_id_seq OWNER TO postgres;

--
-- Name: speedtest_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.speedtest_logs_id_seq OWNED BY public.speedtest_logs.id;


--
-- Name: speedtest_logs id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.speedtest_logs ALTER COLUMN id SET DEFAULT nextval('public.speedtest_logs_id_seq'::regclass);


--
-- Name: speedtest_logs speedtest_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.speedtest_logs
    ADD CONSTRAINT speedtest_logs_pkey PRIMARY KEY (id);


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA public TO netmon;


--
-- Name: TABLE speedtest_logs; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE public.speedtest_logs TO netmon;


--
-- Name: SEQUENCE speedtest_logs_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.speedtest_logs_id_seq TO netmon;


--
-- PostgreSQL database dump complete
--

\unrestrict SVjHG7Og2PUYM7dUWrS0M0osFhhgtpnUmBMvUqTYufHXdpLdkkZbOdOpjefg7Qs

