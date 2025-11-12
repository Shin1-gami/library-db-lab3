CREATE TRIGGER book_versioning_trigger AFTER INSERT OR UPDATE ON public.books FOR EACH ROW EXECUTE FUNCTION public.create_book_version();

CREATE TRIGGER books_audit_trigger AFTER INSERT OR DELETE OR UPDATE ON public.books FOR EACH ROW EXECUTE FUNCTION public.log_books_changes();

INSERT INTO books_versions (book_id, version_number, data)
    VALUES (NEW.book_id, v_version_number, row_to_json(NEW)::jsonb);

