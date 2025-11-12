UPDATE books_versions
    SET valid_to = CURRENT_TIMESTAMP
    WHERE book_id = NEW.book_id AND valid_to IS NULL;

UPDATE books
    SET available_copies = (v_operation.operation_data->>'available_copies')::INTEGER
    WHERE book_id = (v_operation.operation_data->>'book_id')::INTEGER;

UPDATE reservations
    SET status = 'Expired'
    WHERE reservation_id = (v_operation.operation_data->>'reservation_id')::INTEGER;

UPDATE readers
    SET status = 'Blocked'
    WHERE reader_id = (v_operation.operation_data->>'reader_id')::INTEGER;

UPDATE scheduled_operations
    SET status = 'Executed', executed_at = CURRENT_TIMESTAMP
    WHERE operation_id = v_operation.operation_id;

UPDATE scheduled_operations
    SET status = 'Failed',
        executed_at = CURRENT_TIMESTAMP,
        error_message = SQLERRM
    WHERE operation_id = v_operation.operation_id;

UPDATE lendings
    SET due_date = due_date + p_days
    WHERE lending_id = p_lending_id;



SELECT pg_catalog.set_config('search_path', '', false);

SELECT COALESCE(MAX(version_number), 0) + 1
    INTO v_version_number
    FROM books_versions
    WHERE book_id = NEW.book_id;

SELECT * FROM scheduled_operations
        WHERE status = 'Pending' AND scheduled_for <= CURRENT_TIMESTAMP

SELECT r.status, l.due_date, l.reader_id
    INTO v_reader_status, v_current_due_date, v_reader_id
    FROM lendings l
    JOIN readers r ON l.reader_id = r.reader_id
    WHERE l.lending_id = p_lending_id AND l.return_date IS NULL;

SELECT COUNT(*)
    INTO v_overdue_count
    FROM lendings
    WHERE reader_id = v_reader_id
        AND return_date IS NULL
        AND due_date < CURRENT_DATE;

SELECT data
        FROM books_versions
        WHERE book_id = p_book_id
            AND valid_from <= p_date
            AND (valid_to IS NULL OR valid_to > p_date)
        LIMIT 1

SELECT pg_catalog.setval('public.audit_log_log_id_seq', 8, true);

SELECT pg_catalog.setval('public.authors_author_id_seq', 7, true);

SELECT pg_catalog.setval('public.books_book_id_seq', 11, true);

SELECT pg_catalog.setval('public.books_versions_version_id_seq', 3, true);

SELECT pg_catalog.setval('public.lendings_lending_id_seq', 3, true);

SELECT pg_catalog.setval('public.readers_reader_id_seq', 5, true);

SELECT pg_catalog.setval('public.reservations_reservation_id_seq', 3, true);

SELECT pg_catalog.setval('public.scheduled_operations_operation_id_seq', 2, true);

