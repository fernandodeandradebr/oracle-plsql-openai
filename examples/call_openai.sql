-- Run in SQL Developer script mode / SQLcl / SQL*Plus after installation.
-- Populate :api_key and :model_id through your client or secret manager.
-- VARIABLE declares empty binds; this script never prompts for or embeds secrets.
SET DEFINE OFF
SET SERVEROUTPUT ON
VARIABLE api_key VARCHAR2(2000)
VARIABLE model_id VARCHAR2(200)
VARIABLE response_json CLOB

-- Before running the block below, bind api_key and model_id securely.
BEGIN
    openai_chat(
        p_api_key         => :api_key,
        p_model           => :model_id,
        p_prompt          => 'Summarize this incident: the customer reports a late delivery.',
        p_response_json   => :response_json,
        p_timeout_seconds => 30
    );
END;
/

-- Inspect completion status before using the answer.
SELECT JSON_VALUE(:response_json, '$.choices[0].finish_reason') AS finish_reason,
       JSON_VALUE(:response_json, '$.choices[0].message.content'
                  RETURNING VARCHAR2(4000) ERROR ON ERROR) AS answer
FROM dual;

-- Release response memory and clear the key after use.
BEGIN
    IF DBMS_LOB.istemporary(:response_json) = 1 THEN
        DBMS_LOB.freetemporary(:response_json);
    END IF;
    :api_key := NULL;
END;
/
