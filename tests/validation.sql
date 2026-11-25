-- Offline validation checks: no network call is expected.
-- Run after install.sql in an Oracle test database.
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET SERVEROUTPUT ON
DECLARE
    l_response CLOB;
    PROCEDURE expect_rejected(p_prompt VARCHAR2, p_timeout PLS_INTEGER) IS
    BEGIN
        BEGIN
            openai_chat('test-placeholder', 'test-model', p_prompt, l_response, p_timeout);
        EXCEPTION
            WHEN OTHERS THEN
                IF SQLCODE = -20010 THEN RETURN; END IF;
                RAISE;
        END;
        RAISE_APPLICATION_ERROR(-20021, 'Invalid input was unexpectedly accepted.');
    END;
BEGIN
    expect_rejected(NULL, 30);
    expect_rejected(RPAD('x', 4001, 'x'), 30);
    expect_rejected('test', 0);
    expect_rejected('test', 301);
    expect_rejected('test', NULL);
    DBMS_OUTPUT.put_line('Input validation checks passed.');
END;
/
