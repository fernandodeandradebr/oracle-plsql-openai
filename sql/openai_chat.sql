-- Oracle Database 19c reference implementation.
-- Install in a dedicated application schema. No API key is stored by this procedure.
CREATE OR REPLACE PROCEDURE openai_chat (
    p_api_key         IN VARCHAR2,
    p_model           IN VARCHAR2,
    p_prompt          IN VARCHAR2,
    p_response_json   OUT CLOB,
    p_timeout_seconds IN PLS_INTEGER DEFAULT 30
) AUTHID CURRENT_USER AS
    l_req          UTL_HTTP.req;
    l_resp         UTL_HTTP.resp;
    l_req_open     BOOLEAN := FALSE;
    l_resp_open    BOOLEAN := FALSE;
    l_saved        BOOLEAN := FALSE;
    l_timeout      PLS_INTEGER;
    l_detailed     BOOLEAN;
    l_error_check  BOOLEAN;
    l_redirects    PLS_INTEGER;
    l_message      JSON_OBJECT_T := JSON_OBJECT_T();
    l_messages     JSON_ARRAY_T := JSON_ARRAY_T();
    l_payload      JSON_OBJECT_T := JSON_OBJECT_T();
    l_wire         RAW(32767);
    l_chunk        VARCHAR2(32767);
    l_body         CLOB;

    PROCEDURE cleanup IS
    BEGIN
        IF l_resp_open THEN
            BEGIN
                UTL_HTTP.end_response(l_resp);
            EXCEPTION WHEN OTHERS THEN NULL; -- Preserve the original exception.
            END;
            l_resp_open := FALSE;
        ELSIF l_req_open THEN
            BEGIN
                UTL_HTTP.end_request(l_req);
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
        END IF;
        l_req_open := FALSE;
        IF DBMS_LOB.istemporary(l_body) = 1 THEN
            DBMS_LOB.freetemporary(l_body);
        END IF;
        IF l_saved THEN
            UTL_HTTP.set_transfer_timeout(l_timeout);
            UTL_HTTP.set_detailed_excp_support(l_detailed);
            UTL_HTTP.set_response_error_check(l_error_check);
            UTL_HTTP.set_follow_redirect(l_redirects);
            l_saved := FALSE;
        END IF;
    END;
BEGIN
    p_response_json := NULL;
    IF p_api_key IS NULL OR LENGTHB(p_api_key) > 2000
       OR INSTR(p_api_key, CHR(10)) > 0 OR INSTR(p_api_key, CHR(13)) > 0 THEN
        RAISE_APPLICATION_ERROR(-20010, 'Provide a valid API key through a secure bind.');
    END IF;
    IF p_model IS NULL OR LENGTHB(p_model) > 200 THEN
        RAISE_APPLICATION_ERROR(-20010, 'Provide a model ID of at most 200 bytes.');
    END IF;
    IF p_prompt IS NULL OR LENGTHB(p_prompt) > 4000 THEN
        RAISE_APPLICATION_ERROR(-20010, 'Provide a prompt of 1 to 4000 bytes.');
    END IF;
    IF p_timeout_seconds IS NULL OR p_timeout_seconds < 1
       OR p_timeout_seconds > 300 THEN
        RAISE_APPLICATION_ERROR(-20010, 'Read timeout must be between 1 and 300 seconds.');
    END IF;

    -- JSON types escape quotes, line breaks and control characters.
    l_message.put('role', 'user');
    l_message.put('content', p_prompt);
    l_messages.append(l_message);
    l_payload.put('model', p_model);
    l_payload.put('messages', l_messages);
    l_payload.put('stream', FALSE);
    l_payload.put('store', FALSE);
    l_payload.put('max_completion_tokens', 512);
    l_wire := UTL_I18N.string_to_raw(l_payload.to_string(), 'AL32UTF8');

    UTL_HTTP.get_transfer_timeout(l_timeout);
    UTL_HTTP.get_detailed_excp_support(l_detailed);
    UTL_HTTP.get_response_error_check(l_error_check);
    UTL_HTTP.get_follow_redirect(l_redirects);
    l_saved := TRUE;

    -- Read timeout, NOT an end-to-end deadline.
    UTL_HTTP.set_transfer_timeout(p_timeout_seconds);
    UTL_HTTP.set_detailed_excp_support(TRUE);
    UTL_HTTP.set_response_error_check(FALSE);
    UTL_HTTP.set_follow_redirect(0);

    -- Fixed HTTPS endpoint: callers cannot redirect credentials to arbitrary hosts.
    l_req := UTL_HTTP.begin_request(
        'https://api.openai.com/v1/chat/completions', 'POST', 'HTTP/1.1'
    );
    l_req_open := TRUE;
    UTL_HTTP.set_header(l_req, 'Authorization', 'Bearer ' || p_api_key);
    UTL_HTTP.set_header(l_req, 'Content-Type', 'application/json; charset=utf-8');
    UTL_HTTP.set_header(l_req, 'Content-Length', TO_CHAR(UTL_RAW.length(l_wire)));
    UTL_HTTP.write_raw(l_req, l_wire);

    l_resp := UTL_HTTP.get_response(l_req);
    l_resp_open := TRUE;
    l_req_open := FALSE;
    IF l_resp.status_code < 200 OR l_resp.status_code >= 300 THEN
        -- Do not expose provider response bodies, prompts or credentials in errors.
        RAISE_APPLICATION_ERROR(-20011, 'OpenAI returned HTTP ' || l_resp.status_code);
    END IF;

    DBMS_LOB.createtemporary(l_body, TRUE);
    BEGIN
        LOOP
            UTL_HTTP.read_text(l_resp, l_chunk, 8000);
            IF DBMS_LOB.getlength(l_body) + LENGTH(l_chunk) > 1048576 THEN
                RAISE_APPLICATION_ERROR(-20012, 'Response exceeds the 1 Mi-character limit.');
            END IF;
            DBMS_LOB.writeappend(l_body, LENGTH(l_chunk), l_chunk);
        END LOOP;
    EXCEPTION
        WHEN UTL_HTTP.end_of_body THEN NULL;
    END;

    -- Check that the successful response is a JSON object.
    l_payload := JSON_OBJECT_T.parse(l_body);
    UTL_HTTP.end_response(l_resp);
    l_resp_open := FALSE;
    p_response_json := l_body;
    l_body := NULL; -- Transfer temporary LOB ownership to caller.
    cleanup;
EXCEPTION
    WHEN UTL_HTTP.transfer_timeout THEN
        cleanup;
        RAISE_APPLICATION_ERROR(-20013,
            'HTTP read timeout. Remote processing may still continue; do not retry blindly.');
    WHEN OTHERS THEN
        cleanup;
        RAISE;
END;
/
SHOW ERRORS PROCEDURE openai_chat
