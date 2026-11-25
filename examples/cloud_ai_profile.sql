-- ALTERNATIVE integration, independent from openai_chat.sql.
-- Requires installed/configured DBMS_CLOUD and DBMS_CLOUD_AI, grants and network access.
-- Self-managed 19c: consult Oracle's RU 19.30+ installation/capability documentation.
-- Supply these binds securely using your client BEFORE executing the blocks.
-- Do not store API keys as source-code literals.
BEGIN
    DBMS_CLOUD.create_credential(
        credential_name => 'OPENAI_CRED',
        username        => 'OPENAI',
        password        => :api_key
    );
END;
/

DECLARE
    l_attributes JSON_OBJECT_T := JSON_OBJECT_T();
BEGIN
    l_attributes.put('provider', 'openai');
    l_attributes.put('credential_name', 'OPENAI_CRED');
    l_attributes.put('model', :model_id);
    DBMS_CLOUD_AI.create_profile(
        profile_name => 'OPENAI_PROFILE',
        attributes   => l_attributes.to_clob()
    );
END;
/

-- The credential and profile are persistent objects. Create once, not per request.
-- This synchronous call has NO profile timeout configured by this example.
BEGIN
    :response_json := DBMS_CLOUD_AI.generate(
        prompt       => 'Summarize: the customer reports a late delivery.',
        profile_name => 'OPENAI_PROFILE',
        action       => 'chat'
    );
END;
/
-- Here :response_json contains generated text, not the raw OpenAI JSON envelope.
