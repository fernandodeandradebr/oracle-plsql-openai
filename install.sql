-- Run as the application schema, using SQLcl / SQL*Plus / SQL Developer script mode.
WHENEVER SQLERROR EXIT SQL.SQLCODE
@@sql/openai_chat.sql
DECLARE
    l_errors PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO l_errors
    FROM user_errors
    WHERE name = 'OPENAI_CHAT' AND type = 'PROCEDURE';
    IF l_errors > 0 THEN
        RAISE_APPLICATION_ERROR(-20020, 'OPENAI_CHAT has compilation errors; inspect USER_ERRORS.');
    END IF;
END;
/
