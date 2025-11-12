--
-- PostgreSQL database dump
--

\restrict 6POKZJ2GX0WGn0LE0fD8MjtSFUMH03mCZdpCIE5x4WYmlbvgD7CBGS1hkM879Tt

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.6

-- Started on 2025-11-11 23:59:21

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 234 (class 1255 OID 16728)
-- Name: create_book_version(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_book_version() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_version_number INTEGER;
BEGIN
    UPDATE books_versions
    SET valid_to = CURRENT_TIMESTAMP
    WHERE book_id = NEW.book_id AND valid_to IS NULL;

    SELECT COALESCE(MAX(version_number), 0) + 1
    INTO v_version_number
    FROM books_versions
    WHERE book_id = NEW.book_id;

    INSERT INTO books_versions (book_id, version_number, data)
    VALUES (NEW.book_id, v_version_number, row_to_json(NEW)::jsonb);

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.create_book_version() OWNER TO postgres;

--
-- TOC entry 247 (class 1255 OID 16743)
-- Name: execute_scheduled_operations(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.execute_scheduled_operations() RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_operation RECORD;
    v_count INTEGER := 0;
BEGIN
    FOR v_operation IN
        SELECT * FROM scheduled_operations
        WHERE status = 'Pending' AND scheduled_for <= CURRENT_TIMESTAMP
    LOOP
        BEGIN
            CASE v_operation.operation_type
                WHEN 'UPDATE_BOOK_STATUS' THEN
                    UPDATE books
                    SET available_copies = (v_operation.operation_data->>'available_copies')::INTEGER
                    WHERE book_id = (v_operation.operation_data->>'book_id')::INTEGER;

                WHEN 'EXPIRE_RESERVATION' THEN
                    UPDATE reservations
                    SET status = 'Expired'
                    WHERE reservation_id = (v_operation.operation_data->>'reservation_id')::INTEGER;

                WHEN 'BLOCK_READER' THEN
                    UPDATE readers
                    SET status = 'Blocked'
                    WHERE reader_id = (v_operation.operation_data->>'reader_id')::INTEGER;
            END CASE;

            UPDATE scheduled_operations
            SET status = 'Executed', executed_at = CURRENT_TIMESTAMP
            WHERE operation_id = v_operation.operation_id;

            v_count := v_count + 1;
        EXCEPTION WHEN OTHERS THEN
            UPDATE scheduled_operations
            SET status = 'Failed',
                executed_at = CURRENT_TIMESTAMP,
                error_message = SQLERRM
            WHERE operation_id = v_operation.operation_id;
        END;
    END LOOP;

    RETURN v_count;
END;
$$;


ALTER FUNCTION public.execute_scheduled_operations() OWNER TO postgres;

--
-- TOC entry 248 (class 1255 OID 16744)
-- Name: extend_lending(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.extend_lending(p_lending_id integer, p_days integer DEFAULT 7) RETURNS TABLE(success boolean, message text, new_due_date date)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_reader_status VARCHAR(20);
    v_overdue_count INTEGER;
    v_current_due_date DATE;
    v_reader_id INTEGER;
BEGIN
    SELECT r.status, l.due_date, l.reader_id
    INTO v_reader_status, v_current_due_date, v_reader_id
    FROM lendings l
    JOIN readers r ON l.reader_id = r.reader_id
    WHERE l.lending_id = p_lending_id AND l.return_date IS NULL;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'Видача не знайдена або книга вже повернена'::TEXT, NULL::DATE;
        RETURN;
    END IF;

    IF v_reader_status = 'Blocked' THEN
        RETURN QUERY SELECT FALSE, 'Читач заблокований'::TEXT, NULL::DATE;
        RETURN;
    END IF;

    SELECT COUNT(*)
    INTO v_overdue_count
    FROM lendings
    WHERE reader_id = v_reader_id
        AND return_date IS NULL
        AND due_date < CURRENT_DATE;

    IF v_overdue_count > 0 THEN
        RETURN QUERY SELECT FALSE, 'У читача є прострочені книги'::TEXT, NULL::DATE;
        RETURN;
    END IF;

    UPDATE lendings
    SET due_date = due_date + p_days
    WHERE lending_id = p_lending_id;

    RETURN QUERY SELECT TRUE, 'Термін продовжено'::TEXT, (v_current_due_date + p_days)::DATE;
END;
$$;


ALTER FUNCTION public.extend_lending(p_lending_id integer, p_days integer) OWNER TO postgres;

--
-- TOC entry 235 (class 1255 OID 16730)
-- Name: get_book_version(integer, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_book_version(p_book_id integer, p_date timestamp without time zone) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN (
        SELECT data
        FROM books_versions
        WHERE book_id = p_book_id
            AND valid_from <= p_date
            AND (valid_to IS NULL OR valid_to > p_date)
        LIMIT 1
    );
END;
$$;


ALTER FUNCTION public.get_book_version(p_book_id integer, p_date timestamp without time zone) OWNER TO postgres;

--
-- TOC entry 233 (class 1255 OID 16713)
-- Name: log_books_changes(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.log_books_changes() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (table_name, operation, record_id, new_data)
        VALUES ('books', 'INSERT', NEW.book_id, row_to_json(NEW)::jsonb);
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, operation, record_id, old_data, new_data)
        VALUES ('books', 'UPDATE', NEW.book_id, row_to_json(OLD)::jsonb, row_to_json(NEW)::jsonb);
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, operation, record_id, old_data)
        VALUES ('books', 'DELETE', OLD.book_id, row_to_json(OLD)::jsonb);
    END IF;
    RETURN NULL;
END;
$$;


ALTER FUNCTION public.log_books_changes() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 228 (class 1259 OID 16703)
-- Name: audit_log; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.audit_log (
    log_id integer NOT NULL,
    table_name character varying(50) NOT NULL,
    operation character varying(10) NOT NULL,
    record_id integer NOT NULL,
    old_data jsonb,
    new_data jsonb,
    changed_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    changed_by character varying(100) DEFAULT CURRENT_USER
);


ALTER TABLE public.audit_log OWNER TO postgres;

--
-- TOC entry 227 (class 1259 OID 16702)
-- Name: audit_log_log_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.audit_log_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.audit_log_log_id_seq OWNER TO postgres;

--
-- TOC entry 4911 (class 0 OID 0)
-- Dependencies: 227
-- Name: audit_log_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.audit_log_log_id_seq OWNED BY public.audit_log.log_id;


--
-- TOC entry 218 (class 1259 OID 16619)
-- Name: authors; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.authors (
    author_id integer NOT NULL,
    first_name character varying(50) NOT NULL,
    last_name character varying(50) NOT NULL,
    birth_year integer,
    country character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT authors_birth_year_check CHECK (((birth_year >= 1000) AND ((birth_year)::numeric <= EXTRACT(year FROM CURRENT_DATE))))
);


ALTER TABLE public.authors OWNER TO postgres;

--
-- TOC entry 217 (class 1259 OID 16618)
-- Name: authors_author_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.authors_author_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.authors_author_id_seq OWNER TO postgres;

--
-- TOC entry 4912 (class 0 OID 0)
-- Dependencies: 217
-- Name: authors_author_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.authors_author_id_seq OWNED BY public.authors.author_id;


--
-- TOC entry 220 (class 1259 OID 16628)
-- Name: books; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.books (
    book_id integer NOT NULL,
    isbn character varying(17) NOT NULL,
    title character varying(200) NOT NULL,
    author_id integer NOT NULL,
    publication_year integer,
    genre character varying(50),
    total_copies integer DEFAULT 1,
    available_copies integer DEFAULT 1,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT books_available_copies_check CHECK ((available_copies >= 0)),
    CONSTRAINT books_check CHECK ((available_copies <= total_copies)),
    CONSTRAINT books_publication_year_check CHECK ((publication_year >= 1450)),
    CONSTRAINT books_total_copies_check CHECK ((total_copies >= 0))
);


ALTER TABLE public.books OWNER TO postgres;

--
-- TOC entry 219 (class 1259 OID 16627)
-- Name: books_book_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.books_book_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.books_book_id_seq OWNER TO postgres;

--
-- TOC entry 4913 (class 0 OID 0)
-- Dependencies: 219
-- Name: books_book_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.books_book_id_seq OWNED BY public.books.book_id;


--
-- TOC entry 230 (class 1259 OID 16716)
-- Name: books_versions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.books_versions (
    version_id integer NOT NULL,
    book_id integer NOT NULL,
    version_number integer NOT NULL,
    data jsonb NOT NULL,
    valid_from timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    valid_to timestamp without time zone,
    created_by character varying(100) DEFAULT CURRENT_USER
);


ALTER TABLE public.books_versions OWNER TO postgres;

--
-- TOC entry 229 (class 1259 OID 16715)
-- Name: books_versions_version_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.books_versions_version_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.books_versions_version_id_seq OWNER TO postgres;

--
-- TOC entry 4914 (class 0 OID 0)
-- Dependencies: 229
-- Name: books_versions_version_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.books_versions_version_id_seq OWNED BY public.books_versions.version_id;


--
-- TOC entry 224 (class 1259 OID 16663)
-- Name: lendings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.lendings (
    lending_id integer NOT NULL,
    book_id integer NOT NULL,
    reader_id integer NOT NULL,
    lending_date date DEFAULT CURRENT_DATE,
    due_date date NOT NULL,
    return_date date,
    CONSTRAINT lendings_check CHECK ((due_date > lending_date)),
    CONSTRAINT lendings_check1 CHECK (((return_date IS NULL) OR (return_date >= lending_date)))
);


ALTER TABLE public.lendings OWNER TO postgres;

--
-- TOC entry 223 (class 1259 OID 16662)
-- Name: lendings_lending_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.lendings_lending_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.lendings_lending_id_seq OWNER TO postgres;

--
-- TOC entry 4915 (class 0 OID 0)
-- Dependencies: 223
-- Name: lendings_lending_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.lendings_lending_id_seq OWNED BY public.lendings.lending_id;


--
-- TOC entry 222 (class 1259 OID 16649)
-- Name: readers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.readers (
    reader_id integer NOT NULL,
    first_name character varying(50) NOT NULL,
    last_name character varying(50) NOT NULL,
    email character varying(100) NOT NULL,
    phone character varying(20),
    library_card_number character varying(20) NOT NULL,
    registration_date date DEFAULT CURRENT_DATE,
    status character varying(20) DEFAULT 'Active'::character varying,
    CONSTRAINT readers_status_check CHECK (((status)::text = ANY ((ARRAY['Active'::character varying, 'Blocked'::character varying, 'Inactive'::character varying])::text[])))
);


ALTER TABLE public.readers OWNER TO postgres;

--
-- TOC entry 221 (class 1259 OID 16648)
-- Name: readers_reader_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.readers_reader_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.readers_reader_id_seq OWNER TO postgres;

--
-- TOC entry 4916 (class 0 OID 0)
-- Dependencies: 221
-- Name: readers_reader_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.readers_reader_id_seq OWNED BY public.readers.reader_id;


--
-- TOC entry 226 (class 1259 OID 16683)
-- Name: reservations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.reservations (
    reservation_id integer NOT NULL,
    book_id integer NOT NULL,
    reader_id integer NOT NULL,
    reservation_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    expiration_date timestamp without time zone NOT NULL,
    status character varying(20) DEFAULT 'Active'::character varying,
    CONSTRAINT reservations_status_check CHECK (((status)::text = ANY ((ARRAY['Active'::character varying, 'Fulfilled'::character varying, 'Cancelled'::character varying, 'Expired'::character varying])::text[])))
);


ALTER TABLE public.reservations OWNER TO postgres;

--
-- TOC entry 225 (class 1259 OID 16682)
-- Name: reservations_reservation_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.reservations_reservation_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.reservations_reservation_id_seq OWNER TO postgres;

--
-- TOC entry 4917 (class 0 OID 0)
-- Dependencies: 225
-- Name: reservations_reservation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.reservations_reservation_id_seq OWNED BY public.reservations.reservation_id;


--
-- TOC entry 232 (class 1259 OID 16732)
-- Name: scheduled_operations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.scheduled_operations (
    operation_id integer NOT NULL,
    operation_type character varying(50) NOT NULL,
    target_table character varying(50) NOT NULL,
    operation_data jsonb NOT NULL,
    scheduled_for timestamp without time zone NOT NULL,
    status character varying(20) DEFAULT 'Pending'::character varying,
    executed_at timestamp without time zone,
    error_message text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT scheduled_operations_status_check CHECK (((status)::text = ANY ((ARRAY['Pending'::character varying, 'Executed'::character varying, 'Failed'::character varying, 'Cancelled'::character varying])::text[])))
);


ALTER TABLE public.scheduled_operations OWNER TO postgres;

--
-- TOC entry 231 (class 1259 OID 16731)
-- Name: scheduled_operations_operation_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.scheduled_operations_operation_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.scheduled_operations_operation_id_seq OWNER TO postgres;

--
-- TOC entry 4918 (class 0 OID 0)
-- Dependencies: 231
-- Name: scheduled_operations_operation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.scheduled_operations_operation_id_seq OWNED BY public.scheduled_operations.operation_id;


--
-- TOC entry 4695 (class 2604 OID 16706)
-- Name: audit_log log_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_log ALTER COLUMN log_id SET DEFAULT nextval('public.audit_log_log_id_seq'::regclass);


--
-- TOC entry 4681 (class 2604 OID 16622)
-- Name: authors author_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.authors ALTER COLUMN author_id SET DEFAULT nextval('public.authors_author_id_seq'::regclass);


--
-- TOC entry 4683 (class 2604 OID 16631)
-- Name: books book_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.books ALTER COLUMN book_id SET DEFAULT nextval('public.books_book_id_seq'::regclass);


--
-- TOC entry 4698 (class 2604 OID 16719)
-- Name: books_versions version_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.books_versions ALTER COLUMN version_id SET DEFAULT nextval('public.books_versions_version_id_seq'::regclass);


--
-- TOC entry 4690 (class 2604 OID 16666)
-- Name: lendings lending_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lendings ALTER COLUMN lending_id SET DEFAULT nextval('public.lendings_lending_id_seq'::regclass);


--
-- TOC entry 4687 (class 2604 OID 16652)
-- Name: readers reader_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.readers ALTER COLUMN reader_id SET DEFAULT nextval('public.readers_reader_id_seq'::regclass);


--
-- TOC entry 4692 (class 2604 OID 16686)
-- Name: reservations reservation_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservations ALTER COLUMN reservation_id SET DEFAULT nextval('public.reservations_reservation_id_seq'::regclass);


--
-- TOC entry 4701 (class 2604 OID 16735)
-- Name: scheduled_operations operation_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scheduled_operations ALTER COLUMN operation_id SET DEFAULT nextval('public.scheduled_operations_operation_id_seq'::regclass);


--
-- TOC entry 4901 (class 0 OID 16703)
-- Dependencies: 228
-- Data for Name: audit_log; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.audit_log (log_id, table_name, operation, record_id, old_data, new_data, changed_at, changed_by) FROM stdin;
1	books	INSERT	10	\N	{"isbn": "978-966-03-9999-9", "genre": "Сучасна", "title": "Нова книга", "book_id": 10, "author_id": 2, "created_at": "2025-11-11T23:33:16.171131", "total_copies": 5, "available_copies": 5, "publication_year": 2024}	2025-11-11 23:33:16.171131	postgres
2	books	UPDATE	10	{"isbn": "978-966-03-9999-9", "genre": "Сучасна", "title": "Нова книга", "book_id": 10, "author_id": 2, "created_at": "2025-11-11T23:33:16.171131", "total_copies": 5, "available_copies": 5, "publication_year": 2024}	{"isbn": "978-966-03-9999-9", "genre": "Сучасна", "title": "Нова книга", "book_id": 10, "author_id": 2, "created_at": "2025-11-11T23:33:16.171131", "total_copies": 5, "available_copies": 4, "publication_year": 2024}	2025-11-11 23:33:23.133271	postgres
3	books	DELETE	10	{"isbn": "978-966-03-9999-9", "genre": "Сучасна", "title": "Нова книга", "book_id": 10, "author_id": 2, "created_at": "2025-11-11T23:33:16.171131", "total_copies": 5, "available_copies": 4, "publication_year": 2024}	\N	2025-11-11 23:33:29.525283	postgres
4	books	UPDATE	1	{"isbn": "978-966-03-4561-2", "genre": "Поезія", "title": "Кобзар", "book_id": 1, "author_id": 1, "created_at": "2025-11-11T20:54:20.083653", "total_copies": 12, "available_copies": 7, "publication_year": 1840}	{"isbn": "978-966-03-4561-2", "genre": "Поезія", "title": "Кобзар", "book_id": 1, "author_id": 1, "created_at": "2025-11-11T20:54:20.083653", "total_copies": 12, "available_copies": 6, "publication_year": 1840}	2025-11-11 23:35:29.442399	postgres
5	books	UPDATE	1	{"isbn": "978-966-03-4561-2", "genre": "Поезія", "title": "Кобзар", "book_id": 1, "author_id": 1, "created_at": "2025-11-11T20:54:20.083653", "total_copies": 12, "available_copies": 6, "publication_year": 1840}	{"isbn": "978-966-03-4561-2", "genre": "Поезія", "title": "Кобзар", "book_id": 1, "author_id": 1, "created_at": "2025-11-11T20:54:20.083653", "total_copies": 12, "available_copies": 5, "publication_year": 1840}	2025-11-11 23:36:22.118695	postgres
6	books	INSERT	11	\N	{"isbn": "978-966-03-7777-7", "genre": "Тест", "title": "Версійована книга", "book_id": 11, "author_id": 3, "created_at": "2025-11-11T23:40:49.655162", "total_copies": 10, "available_copies": 10, "publication_year": 2020}	2025-11-11 23:40:49.655162	postgres
7	books	UPDATE	11	{"isbn": "978-966-03-7777-7", "genre": "Тест", "title": "Версійована книга", "book_id": 11, "author_id": 3, "created_at": "2025-11-11T23:40:49.655162", "total_copies": 10, "available_copies": 10, "publication_year": 2020}	{"isbn": "978-966-03-7777-7", "genre": "Тест", "title": "Версійована книга", "book_id": 11, "author_id": 3, "created_at": "2025-11-11T23:40:49.655162", "total_copies": 10, "available_copies": 8, "publication_year": 2020}	2025-11-11 23:40:49.655162	postgres
8	books	UPDATE	11	{"isbn": "978-966-03-7777-7", "genre": "Тест", "title": "Версійована книга", "book_id": 11, "author_id": 3, "created_at": "2025-11-11T23:40:49.655162", "total_copies": 10, "available_copies": 8, "publication_year": 2020}	{"isbn": "978-966-03-7777-7", "genre": "Оновлений жанр", "title": "Версійована книга", "book_id": 11, "author_id": 3, "created_at": "2025-11-11T23:40:49.655162", "total_copies": 10, "available_copies": 5, "publication_year": 2020}	2025-11-11 23:40:49.655162	postgres
\.


--
-- TOC entry 4891 (class 0 OID 16619)
-- Dependencies: 218
-- Data for Name: authors; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.authors (author_id, first_name, last_name, birth_year, country, created_at) FROM stdin;
1	Тарас	Шевченко	1814	Україна	2025-11-11 20:53:10.0757
2	Іван	Франко	1856	Україна	2025-11-11 20:53:10.0757
3	Леся	Українка	1871	Україна	2025-11-11 20:53:10.0757
4	Михайло	Коцюбинський	1864	Україна	2025-11-11 20:53:10.0757
5	Панас	Мирний	1849	Україна	2025-11-11 20:53:10.0757
6	Ольга	Кобилянська	1863	Україна	2025-11-11 23:24:09.85544
\.


--
-- TOC entry 4893 (class 0 OID 16628)
-- Dependencies: 220
-- Data for Name: books; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.books (book_id, isbn, title, author_id, publication_year, genre, total_copies, available_copies, created_at) FROM stdin;
2	978-966-03-4562-9	Захар Беркут	2	1883	Історична проза	5	4	2025-11-11 20:54:20.083653
3	978-966-03-4563-6	Лісова пісня	3	1911	Драма	7	7	2025-11-11 20:54:20.083653
4	978-966-03-4564-3	Тіні забутих предків	4	1911	Повість	6	5	2025-11-11 20:54:20.083653
5	978-966-03-4565-0	Хіба ревуть воли, як ясла повні	5	1880	Повість	4	4	2025-11-11 20:54:20.083653
6	978-966-03-4566-7	Земля	6	1902	Роман	3	3	2025-11-11 23:24:09.85544
8	978-966-03-4567-4	Царівна	6	1896	Повість	2	2	2025-11-11 23:24:09.85544
1	978-966-03-4561-2	Кобзар	1	1840	Поезія	12	5	2025-11-11 20:54:20.083653
11	978-966-03-7777-7	Версійована книга	3	2020	Оновлений жанр	10	5	2025-11-11 23:40:49.655162
\.


--
-- TOC entry 4903 (class 0 OID 16716)
-- Dependencies: 230
-- Data for Name: books_versions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.books_versions (version_id, book_id, version_number, data, valid_from, valid_to, created_by) FROM stdin;
1	11	1	{"isbn": "978-966-03-7777-7", "genre": "Тест", "title": "Версійована книга", "book_id": 11, "author_id": 3, "created_at": "2025-11-11T23:40:49.655162", "total_copies": 10, "available_copies": 10, "publication_year": 2020}	2025-11-11 23:40:49.655162	2025-11-11 23:40:49.655162	postgres
2	11	2	{"isbn": "978-966-03-7777-7", "genre": "Тест", "title": "Версійована книга", "book_id": 11, "author_id": 3, "created_at": "2025-11-11T23:40:49.655162", "total_copies": 10, "available_copies": 8, "publication_year": 2020}	2025-11-11 23:40:49.655162	2025-11-11 23:40:49.655162	postgres
3	11	3	{"isbn": "978-966-03-7777-7", "genre": "Оновлений жанр", "title": "Версійована книга", "book_id": 11, "author_id": 3, "created_at": "2025-11-11T23:40:49.655162", "total_copies": 10, "available_copies": 5, "publication_year": 2020}	2025-11-11 23:40:49.655162	\N	postgres
\.


--
-- TOC entry 4897 (class 0 OID 16663)
-- Dependencies: 224
-- Data for Name: lendings; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.lendings (lending_id, book_id, reader_id, lending_date, due_date, return_date) FROM stdin;
1	1	1	2025-11-11	2025-11-25	2025-11-11
2	2	2	2025-11-11	2025-12-02	\N
3	3	2	2025-10-22	2025-11-06	\N
\.


--
-- TOC entry 4895 (class 0 OID 16649)
-- Dependencies: 222
-- Data for Name: readers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.readers (reader_id, first_name, last_name, email, phone, library_card_number, registration_date, status) FROM stdin;
1	Олена	Петренко	olena.petrenko@email.com	+380501234567	LIB-2024-001	2025-11-11	Active
3	Марія	Сидоренко	maria.sydorenko@email.com	+380503456789	LIB-2024-003	2025-11-11	Active
4	Іван	Мельник	ivan.melnyk@email.com	+380504567890	LIB-2024-004	2025-11-11	Active
2	Андрій	Коваленко	andrii.kovalenko@email.com	+380502345678	LIB-2024-002	2025-11-11	Active
\.


--
-- TOC entry 4899 (class 0 OID 16683)
-- Dependencies: 226
-- Data for Name: reservations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.reservations (reservation_id, book_id, reader_id, reservation_date, expiration_date, status) FROM stdin;
1	1	2	2025-11-11 23:20:08.840131	2025-11-14 23:20:08.840131	Fulfilled
2	8	1	2025-11-11 23:29:05.553505	2025-11-18 23:29:05.553505	Active
3	2	3	2025-11-11 23:43:02.466151	2025-11-11 23:44:02.466151	Active
\.


--
-- TOC entry 4905 (class 0 OID 16732)
-- Dependencies: 232
-- Data for Name: scheduled_operations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.scheduled_operations (operation_id, operation_type, target_table, operation_data, scheduled_for, status, executed_at, error_message, created_at) FROM stdin;
1	EXPIRE_RESERVATION	reservations	{"reservation_id": 3}	2025-11-11 23:45:12.669521	Pending	\N	\N	2025-11-11 23:43:12.669521
2	BLOCK_READER	readers	{"reader_id": 4}	2025-11-11 23:48:51.329857	Pending	\N	\N	2025-11-11 23:43:51.329857
\.


--
-- TOC entry 4919 (class 0 OID 0)
-- Dependencies: 227
-- Name: audit_log_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.audit_log_log_id_seq', 8, true);


--
-- TOC entry 4920 (class 0 OID 0)
-- Dependencies: 217
-- Name: authors_author_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.authors_author_id_seq', 7, true);


--
-- TOC entry 4921 (class 0 OID 0)
-- Dependencies: 219
-- Name: books_book_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.books_book_id_seq', 11, true);


--
-- TOC entry 4922 (class 0 OID 0)
-- Dependencies: 229
-- Name: books_versions_version_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.books_versions_version_id_seq', 3, true);


--
-- TOC entry 4923 (class 0 OID 0)
-- Dependencies: 223
-- Name: lendings_lending_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.lendings_lending_id_seq', 3, true);


--
-- TOC entry 4924 (class 0 OID 0)
-- Dependencies: 221
-- Name: readers_reader_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.readers_reader_id_seq', 5, true);


--
-- TOC entry 4925 (class 0 OID 0)
-- Dependencies: 225
-- Name: reservations_reservation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.reservations_reservation_id_seq', 3, true);


--
-- TOC entry 4926 (class 0 OID 0)
-- Dependencies: 231
-- Name: scheduled_operations_operation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.scheduled_operations_operation_id_seq', 2, true);


--
-- TOC entry 4731 (class 2606 OID 16712)
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (log_id);


--
-- TOC entry 4715 (class 2606 OID 16626)
-- Name: authors authors_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.authors
    ADD CONSTRAINT authors_pkey PRIMARY KEY (author_id);


--
-- TOC entry 4717 (class 2606 OID 16642)
-- Name: books books_isbn_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.books
    ADD CONSTRAINT books_isbn_key UNIQUE (isbn);


--
-- TOC entry 4719 (class 2606 OID 16640)
-- Name: books books_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.books
    ADD CONSTRAINT books_pkey PRIMARY KEY (book_id);


--
-- TOC entry 4733 (class 2606 OID 16727)
-- Name: books_versions books_versions_book_id_version_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.books_versions
    ADD CONSTRAINT books_versions_book_id_version_number_key UNIQUE (book_id, version_number);


--
-- TOC entry 4735 (class 2606 OID 16725)
-- Name: books_versions books_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.books_versions
    ADD CONSTRAINT books_versions_pkey PRIMARY KEY (version_id);


--
-- TOC entry 4727 (class 2606 OID 16671)
-- Name: lendings lendings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lendings
    ADD CONSTRAINT lendings_pkey PRIMARY KEY (lending_id);


--
-- TOC entry 4721 (class 2606 OID 16659)
-- Name: readers readers_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.readers
    ADD CONSTRAINT readers_email_key UNIQUE (email);


--
-- TOC entry 4723 (class 2606 OID 16661)
-- Name: readers readers_library_card_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.readers
    ADD CONSTRAINT readers_library_card_number_key UNIQUE (library_card_number);


--
-- TOC entry 4725 (class 2606 OID 16657)
-- Name: readers readers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.readers
    ADD CONSTRAINT readers_pkey PRIMARY KEY (reader_id);


--
-- TOC entry 4729 (class 2606 OID 16691)
-- Name: reservations reservations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservations
    ADD CONSTRAINT reservations_pkey PRIMARY KEY (reservation_id);


--
-- TOC entry 4737 (class 2606 OID 16742)
-- Name: scheduled_operations scheduled_operations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scheduled_operations
    ADD CONSTRAINT scheduled_operations_pkey PRIMARY KEY (operation_id);


--
-- TOC entry 4743 (class 2620 OID 16729)
-- Name: books book_versioning_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER book_versioning_trigger AFTER INSERT OR UPDATE ON public.books FOR EACH ROW EXECUTE FUNCTION public.create_book_version();


--
-- TOC entry 4744 (class 2620 OID 16714)
-- Name: books books_audit_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER books_audit_trigger AFTER INSERT OR DELETE OR UPDATE ON public.books FOR EACH ROW EXECUTE FUNCTION public.log_books_changes();


--
-- TOC entry 4738 (class 2606 OID 16643)
-- Name: books books_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.books
    ADD CONSTRAINT books_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.authors(author_id) ON DELETE RESTRICT;


--
-- TOC entry 4739 (class 2606 OID 16672)
-- Name: lendings lendings_book_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lendings
    ADD CONSTRAINT lendings_book_id_fkey FOREIGN KEY (book_id) REFERENCES public.books(book_id) ON DELETE RESTRICT;


--
-- TOC entry 4740 (class 2606 OID 16677)
-- Name: lendings lendings_reader_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lendings
    ADD CONSTRAINT lendings_reader_id_fkey FOREIGN KEY (reader_id) REFERENCES public.readers(reader_id) ON DELETE RESTRICT;


--
-- TOC entry 4741 (class 2606 OID 16692)
-- Name: reservations reservations_book_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservations
    ADD CONSTRAINT reservations_book_id_fkey FOREIGN KEY (book_id) REFERENCES public.books(book_id) ON DELETE CASCADE;


--
-- TOC entry 4742 (class 2606 OID 16697)
-- Name: reservations reservations_reader_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservations
    ADD CONSTRAINT reservations_reader_id_fkey FOREIGN KEY (reader_id) REFERENCES public.readers(reader_id) ON DELETE CASCADE;


-- Completed on 2025-11-11 23:59:21

--
-- PostgreSQL database dump complete
--

\unrestrict 6POKZJ2GX0WGn0LE0fD8MjtSFUMH03mCZdpCIE5x4WYmlbvgD7CBGS1hkM879Tt

