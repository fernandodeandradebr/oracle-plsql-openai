-- DBA-only example for a self-managed Oracle 19c installation.
-- Replace APP_SCHEMA with the exact application user name before execution.
-- Review existing ACL entries first. This is intentionally not run by install.sql.
BEGIN
    DBMS_NETWORK_ACL_ADMIN.append_host_ace(
        host       => 'api.openai.com',
        lower_port => 443,
        upper_port => 443,
        ace        => XS$ACE_TYPE(
            privilege_list => XS$NAME_LIST('connect'),
            principal_name => 'APP_SCHEMA',
            principal_type => XS_ACL.ptype_db
        )
    );
END;
/
-- The application schema also needs access to UTL_HTTP, UTL_I18N and DBMS_LOB.
-- If not already available, the DBA must grant the required EXECUTE privileges.
-- Configure outbound DNS/firewall access and trusted HTTPS certificates separately.
-- In the calling session, use a DBA-provisioned auto-login trust wallet if needed:
-- BEGIN
--     UTL_HTTP.set_wallet('file:/path/to/trust-wallet', NULL);
-- END;
-- /
-- Do not disable certificate verification. Never commit wallet files.
