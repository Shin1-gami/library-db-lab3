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

CREATE TABLE public.authors (
    author_id integer NOT NULL,
    first_name character varying(50) NOT NULL,
    last_name character varying(50) NOT NULL,
    birth_year integer,
    country character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT authors_birth_year_check CHECK (((birth_year >= 1000) AND ((birth_year)::numeric <= EXTRACT(year FROM CURRENT_DATE))))
);

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

CREATE TABLE public.books_versions (
    version_id integer NOT NULL,
    book_id integer NOT NULL,
    version_number integer NOT NULL,
    data jsonb NOT NULL,
    valid_from timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    valid_to timestamp without time zone,
    created_by character varying(100) DEFAULT CURRENT_USER
);

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

CREATE TABLE public.reservations (
    reservation_id integer NOT NULL,
    book_id integer NOT NULL,
    reader_id integer NOT NULL,
    reservation_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    expiration_date timestamp without time zone NOT NULL,
    status character varying(20) DEFAULT 'Active'::character varying,
    CONSTRAINT reservations_status_check CHECK (((status)::text = ANY ((ARRAY['Active'::character varying, 'Fulfilled'::character varying, 'Cancelled'::character varying, 'Expired'::character varying])::text[])))
);

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



ALTER TABLE ONLY public.books
    ADD CONSTRAINT books_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.authors(author_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.lendings
    ADD CONSTRAINT lendings_book_id_fkey FOREIGN KEY (book_id) REFERENCES public.books(book_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.lendings
    ADD CONSTRAINT lendings_reader_id_fkey FOREIGN KEY (reader_id) REFERENCES public.readers(reader_id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.reservations
    ADD CONSTRAINT reservations_book_id_fkey FOREIGN KEY (book_id) REFERENCES public.books(book_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.reservations
    ADD CONSTRAINT reservations_reader_id_fkey FOREIGN KEY (reader_id) REFERENCES public.readers(reader_id) ON DELETE CASCADE;

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (log_id);

ALTER TABLE ONLY public.authors
    ADD CONSTRAINT authors_pkey PRIMARY KEY (author_id);

ALTER TABLE ONLY public.books
    ADD CONSTRAINT books_isbn_key UNIQUE (isbn);

ALTER TABLE ONLY public.books
    ADD CONSTRAINT books_pkey PRIMARY KEY (book_id);

ALTER TABLE ONLY public.books_versions
    ADD CONSTRAINT books_versions_book_id_version_number_key UNIQUE (book_id, version_number);

ALTER TABLE ONLY public.books_versions
    ADD CONSTRAINT books_versions_pkey PRIMARY KEY (version_id);

ALTER TABLE ONLY public.lendings
    ADD CONSTRAINT lendings_pkey PRIMARY KEY (lending_id);

ALTER TABLE ONLY public.readers
    ADD CONSTRAINT readers_email_key UNIQUE (email);

ALTER TABLE ONLY public.readers
    ADD CONSTRAINT readers_library_card_number_key UNIQUE (library_card_number);

ALTER TABLE ONLY public.readers
    ADD CONSTRAINT readers_pkey PRIMARY KEY (reader_id);

ALTER TABLE ONLY public.reservations
    ADD CONSTRAINT reservations_pkey PRIMARY KEY (reservation_id);

ALTER TABLE ONLY public.scheduled_operations
    ADD CONSTRAINT scheduled_operations_pkey PRIMARY KEY (operation_id);