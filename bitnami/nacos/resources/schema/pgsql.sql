-- Nacos PostgreSQL Schema (Idempotent)
-- Compatible with Nacos 3.0.x
-- https://github.com/alibaba/nacos

CREATE TABLE IF NOT EXISTS config_info (
    id BIGSERIAL PRIMARY KEY,
    data_id VARCHAR(255) NOT NULL,
    group_id VARCHAR(255),
    content TEXT NOT NULL,
    md5 VARCHAR(32),
    gmt_create TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    gmt_modified TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    src_user TEXT,
    src_ip VARCHAR(50),
    app_name VARCHAR(128),
    tenant_id VARCHAR(128) DEFAULT '',
    c_desc VARCHAR(256),
    c_use VARCHAR(64),
    effect VARCHAR(64),
    type VARCHAR(64),
    c_schema TEXT,
    encrypted_data_key VARCHAR(1024) DEFAULT '',
    CONSTRAINT uk_configinfo_datagrouptenant UNIQUE (data_id, group_id, tenant_id)
);

CREATE TABLE IF NOT EXISTS config_info_aggr (
    id BIGSERIAL PRIMARY KEY,
    data_id VARCHAR(255) NOT NULL,
    group_id VARCHAR(255) NOT NULL,
    datum_id VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    gmt_modified TIMESTAMP NOT NULL,
    app_name VARCHAR(128),
    tenant_id VARCHAR(128) DEFAULT '',
    CONSTRAINT uk_configinfoaggr_datagrouptenantdatum UNIQUE (data_id, group_id, tenant_id, datum_id)
);

CREATE TABLE IF NOT EXISTS config_info_beta (
    id BIGSERIAL PRIMARY KEY,
    data_id VARCHAR(255) NOT NULL,
    group_id VARCHAR(128) NOT NULL,
    app_name VARCHAR(128),
    content TEXT NOT NULL,
    beta_ips VARCHAR(1024),
    md5 VARCHAR(32),
    gmt_create TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    gmt_modified TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    src_user TEXT,
    src_ip VARCHAR(50),
    tenant_id VARCHAR(128) DEFAULT '',
    encrypted_data_key VARCHAR(1024) DEFAULT '',
    CONSTRAINT uk_configinfobeta_datagrouptenant UNIQUE (data_id, group_id, tenant_id)
);

CREATE TABLE IF NOT EXISTS config_info_tag (
    id BIGSERIAL PRIMARY KEY,
    data_id VARCHAR(255) NOT NULL,
    group_id VARCHAR(128) NOT NULL,
    tenant_id VARCHAR(128) DEFAULT '',
    tag_id VARCHAR(128) NOT NULL,
    app_name VARCHAR(128),
    content TEXT NOT NULL,
    md5 VARCHAR(32),
    gmt_create TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    gmt_modified TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    src_user TEXT,
    src_ip VARCHAR(50),
    encrypted_data_key VARCHAR(1024) DEFAULT '',
    CONSTRAINT uk_configinfotag_datagrouptenanttag UNIQUE (data_id, group_id, tenant_id, tag_id)
);

CREATE TABLE IF NOT EXISTS config_info_gray (
    id BIGSERIAL PRIMARY KEY,
    data_id VARCHAR(255) NOT NULL,
    group_id VARCHAR(128) NOT NULL,
    content TEXT NOT NULL,
    md5 VARCHAR(32),
    src_user TEXT,
    src_ip VARCHAR(100),
    gmt_create TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    gmt_modified TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    app_name VARCHAR(128),
    tenant_id VARCHAR(128) DEFAULT '',
    gray_name VARCHAR(128) NOT NULL,
    gray_rule TEXT NOT NULL,
    encrypted_data_key VARCHAR(256) DEFAULT '',
    CONSTRAINT uk_configinfogray_datagrouptenantgray UNIQUE (data_id, group_id, tenant_id, gray_name)
);
CREATE INDEX IF NOT EXISTS idx_gray_dataid_gmt_modified ON config_info_gray(data_id, gmt_modified);
CREATE INDEX IF NOT EXISTS idx_gray_gmt_modified ON config_info_gray(gmt_modified);

CREATE TABLE IF NOT EXISTS config_tags_relation (
    id BIGINT NOT NULL,
    tag_name VARCHAR(128) NOT NULL,
    tag_type VARCHAR(64),
    data_id VARCHAR(255) NOT NULL,
    group_id VARCHAR(128) NOT NULL,
    tenant_id VARCHAR(128) DEFAULT '',
    nid BIGSERIAL PRIMARY KEY,
    CONSTRAINT uk_configtagrelation_configidtag UNIQUE (id, tag_name, tag_type)
);
CREATE INDEX IF NOT EXISTS idx_tags_tenant_id ON config_tags_relation(tenant_id);

CREATE TABLE IF NOT EXISTS group_capacity (
    id BIGSERIAL PRIMARY KEY,
    group_id VARCHAR(128) NOT NULL DEFAULT '',
    quota INT NOT NULL DEFAULT 0,
    usage INT NOT NULL DEFAULT 0,
    max_size INT NOT NULL DEFAULT 0,
    max_aggr_count INT NOT NULL DEFAULT 0,
    max_aggr_size INT NOT NULL DEFAULT 0,
    max_history_count INT NOT NULL DEFAULT 0,
    gmt_create TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    gmt_modified TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_group_id UNIQUE (group_id)
);

CREATE TABLE IF NOT EXISTS his_config_info (
    id BIGINT NOT NULL,
    nid BIGSERIAL PRIMARY KEY,
    data_id VARCHAR(255) NOT NULL,
    group_id VARCHAR(128) NOT NULL,
    app_name VARCHAR(128),
    content TEXT NOT NULL,
    md5 VARCHAR(32),
    gmt_create TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    gmt_modified TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    src_user TEXT,
    src_ip VARCHAR(50),
    op_type CHAR(10),
    tenant_id VARCHAR(128) DEFAULT '',
    encrypted_data_key VARCHAR(1024) DEFAULT '',
    publish_type VARCHAR(50) DEFAULT 'formal',
    gray_name VARCHAR(50),
    ext_info TEXT
);
CREATE INDEX IF NOT EXISTS idx_his_gmt_create ON his_config_info(gmt_create);
CREATE INDEX IF NOT EXISTS idx_his_gmt_modified ON his_config_info(gmt_modified);
CREATE INDEX IF NOT EXISTS idx_his_did ON his_config_info(data_id);

CREATE TABLE IF NOT EXISTS tenant_capacity (
    id BIGSERIAL PRIMARY KEY,
    tenant_id VARCHAR(128) NOT NULL DEFAULT '',
    quota INT NOT NULL DEFAULT 0,
    usage INT NOT NULL DEFAULT 0,
    max_size INT NOT NULL DEFAULT 0,
    max_aggr_count INT NOT NULL DEFAULT 0,
    max_aggr_size INT NOT NULL DEFAULT 0,
    max_history_count INT NOT NULL DEFAULT 0,
    gmt_create TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    gmt_modified TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_tenant_id UNIQUE (tenant_id)
);

CREATE TABLE IF NOT EXISTS tenant_info (
    id BIGSERIAL PRIMARY KEY,
    kp VARCHAR(128) NOT NULL,
    tenant_id VARCHAR(128) DEFAULT '',
    tenant_name VARCHAR(128) DEFAULT '',
    tenant_desc VARCHAR(256),
    create_source VARCHAR(32),
    gmt_create BIGINT NOT NULL,
    gmt_modified BIGINT NOT NULL,
    CONSTRAINT uk_tenant_info_kptenantid UNIQUE (kp, tenant_id)
);
CREATE INDEX IF NOT EXISTS idx_tenant_id_info ON tenant_info(tenant_id);

CREATE TABLE IF NOT EXISTS users (
    username VARCHAR(50) PRIMARY KEY,
    password VARCHAR(500) NOT NULL,
    enabled BOOLEAN NOT NULL
);

CREATE TABLE IF NOT EXISTS roles (
    username VARCHAR(50) NOT NULL,
    role VARCHAR(50) NOT NULL,
    CONSTRAINT idx_user_role UNIQUE (username, role)
);

CREATE TABLE IF NOT EXISTS permissions (
    role VARCHAR(50) NOT NULL,
    resource VARCHAR(255) NOT NULL,
    action VARCHAR(8) NOT NULL,
    CONSTRAINT uk_role_permission UNIQUE (role, resource, action)
);
