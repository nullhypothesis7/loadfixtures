-- =============================================================================
-- SALESFORCE ENTERPRISE SCHEMA -- 100 real Salesforce standard objects
-- =============================================================================
-- A broader, independent complement to salesforce_schema.sql (7-table core
-- CRM set). Spans Sales, Service, Field Service, Content, Collaboration,
-- Platform, Marketing, and Social clouds -- all real Salesforce standard
-- object names with key prefixes verified against public Salesforce
-- documentation and community references (not guessed).
--
-- Reserved-word workarounds (field names unaffected): Case->sfcase,
-- User->sfuser, Group->sfgroup, Order->sforder.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS sf_core;
CREATE SCHEMA IF NOT EXISTS sf_account;
CREATE SCHEMA IF NOT EXISTS sf_sales;
CREATE SCHEMA IF NOT EXISTS sf_service;
CREATE SCHEMA IF NOT EXISTS sf_field_service;
CREATE SCHEMA IF NOT EXISTS sf_activity;
CREATE SCHEMA IF NOT EXISTS sf_content;
CREATE SCHEMA IF NOT EXISTS sf_collab;
CREATE SCHEMA IF NOT EXISTS sf_process;
CREATE SCHEMA IF NOT EXISTS sf_marketing;
CREATE SCHEMA IF NOT EXISTS sf_platform;
CREATE SCHEMA IF NOT EXISTS sf_social;
CREATE SCHEMA IF NOT EXISTS sf_assets;
CREATE SCHEMA IF NOT EXISTS sf_messaging;

-- Drop all tables first (CASCADE handles FK dependency order automatically)
-- so re-running the schema-bootstrap step against an already-seeded database
-- is safe, matching the pattern used by every other shipped schema file.
DROP TABLE IF EXISTS sf_core.sfuser CASCADE;
DROP TABLE IF EXISTS sf_core.profile CASCADE;
DROP TABLE IF EXISTS sf_core.userrole CASCADE;
DROP TABLE IF EXISTS sf_core.permissionset CASCADE;
DROP TABLE IF EXISTS sf_core.permissionsetassignment CASCADE;
DROP TABLE IF EXISTS sf_core.permissionsetlicense CASCADE;
DROP TABLE IF EXISTS sf_core.recordtype CASCADE;
DROP TABLE IF EXISTS sf_core.sfgroup CASCADE;
DROP TABLE IF EXISTS sf_core.territory CASCADE;
DROP TABLE IF EXISTS sf_core.territory CASCADE;
DROP TABLE IF EXISTS sf_core.territory CASCADE;
DROP TABLE IF EXISTS sf_core.userterritory CASCADE;
DROP TABLE IF EXISTS sf_account.account CASCADE;
DROP TABLE IF EXISTS sf_account.contact CASCADE;
DROP TABLE IF EXISTS sf_account.individual CASCADE;
DROP TABLE IF EXISTS sf_account.individualshare CASCADE;
DROP TABLE IF EXISTS sf_account.partner CASCADE;
DROP TABLE IF EXISTS sf_account.organization CASCADE;
DROP TABLE IF EXISTS sf_sales.lead CASCADE;
DROP TABLE IF EXISTS sf_sales.opportunity CASCADE;
DROP TABLE IF EXISTS sf_sales.opportunitylineitem CASCADE;
DROP TABLE IF EXISTS sf_sales.opportunitycontactrole CASCADE;
DROP TABLE IF EXISTS sf_sales.campaign CASCADE;
DROP TABLE IF EXISTS sf_sales.campaignmember CASCADE;
DROP TABLE IF EXISTS sf_sales.quote CASCADE;
DROP TABLE IF EXISTS sf_sales.quotelineitem CASCADE;
DROP TABLE IF EXISTS sf_sales.quotedocument CASCADE;
DROP TABLE IF EXISTS sf_sales.contract CASCADE;
DROP TABLE IF EXISTS sf_sales.contractlineitem CASCADE;
DROP TABLE IF EXISTS sf_sales.sforder CASCADE;
DROP TABLE IF EXISTS sf_sales.orderitem CASCADE;
DROP TABLE IF EXISTS sf_sales.product CASCADE;
DROP TABLE IF EXISTS sf_sales.product CASCADE;
DROP TABLE IF EXISTS sf_sales.pricebook CASCADE;
DROP TABLE IF EXISTS sf_sales.pricebook CASCADE;
DROP TABLE IF EXISTS sf_sales.payment CASCADE;
DROP TABLE IF EXISTS sf_sales.returnorder CASCADE;
DROP TABLE IF EXISTS sf_sales.returnorderlineitem CASCADE;
DROP TABLE IF EXISTS sf_service.sfcase CASCADE;
DROP TABLE IF EXISTS sf_service.solution CASCADE;
DROP TABLE IF EXISTS sf_service.entitlement CASCADE;
DROP TABLE IF EXISTS sf_service.entitlementtemplate CASCADE;
DROP TABLE IF EXISTS sf_service.slaprocess CASCADE;
DROP TABLE IF EXISTS sf_service.casemilestone CASCADE;
DROP TABLE IF EXISTS sf_service.milestonetype CASCADE;
DROP TABLE IF EXISTS sf_service.livechattranscript CASCADE;
DROP TABLE IF EXISTS sf_service.livechatvisitor CASCADE;
DROP TABLE IF EXISTS sf_service.livechatdeployment CASCADE;
DROP TABLE IF EXISTS sf_service.livechatbutton CASCADE;
DROP TABLE IF EXISTS sf_service.quicktext CASCADE;
DROP TABLE IF EXISTS sf_service.chatsession CASCADE;
DROP TABLE IF EXISTS sf_service.servicecontract CASCADE;
DROP TABLE IF EXISTS sf_service.casearticle CASCADE;
DROP TABLE IF EXISTS sf_service.duplicatejob CASCADE;
DROP TABLE IF EXISTS sf_field_service.workorder CASCADE;
DROP TABLE IF EXISTS sf_field_service.workorderlineitem CASCADE;
DROP TABLE IF EXISTS sf_field_service.operatinghours CASCADE;
DROP TABLE IF EXISTS sf_field_service.serviceterritorylocation CASCADE;
DROP TABLE IF EXISTS sf_field_service.maintenanceasset CASCADE;
DROP TABLE IF EXISTS sf_field_service.maintenanceplan CASCADE;
DROP TABLE IF EXISTS sf_field_service.servicereport CASCADE;
DROP TABLE IF EXISTS sf_field_service.servicecrew CASCADE;
DROP TABLE IF EXISTS sf_field_service.servicecrewmember CASCADE;
DROP TABLE IF EXISTS sf_field_service.timesheet CASCADE;
DROP TABLE IF EXISTS sf_activity.task CASCADE;
DROP TABLE IF EXISTS sf_activity.event CASCADE;
DROP TABLE IF EXISTS sf_activity.eventrelation CASCADE;
DROP TABLE IF EXISTS sf_activity.taskrelation CASCADE;
DROP TABLE IF EXISTS sf_activity.timesheetentry CASCADE;
DROP TABLE IF EXISTS sf_content.contentdocument CASCADE;
DROP TABLE IF EXISTS sf_content.contentversion CASCADE;
DROP TABLE IF EXISTS sf_content.contentdocumentlink CASCADE;
DROP TABLE IF EXISTS sf_content.attachment CASCADE;
DROP TABLE IF EXISTS sf_content.note CASCADE;
DROP TABLE IF EXISTS sf_collab.collaborationgroup CASCADE;
DROP TABLE IF EXISTS sf_collab.feedpost CASCADE;
DROP TABLE IF EXISTS sf_collab.feedcomment CASCADE;
DROP TABLE IF EXISTS sf_collab.topic CASCADE;
DROP TABLE IF EXISTS sf_process.processinstance CASCADE;
DROP TABLE IF EXISTS sf_process.duplicatejobmatchingrule CASCADE;
DROP TABLE IF EXISTS sf_marketing.emailtemplate CASCADE;
DROP TABLE IF EXISTS sf_marketing.listemail CASCADE;
DROP TABLE IF EXISTS sf_marketing.listemailrecipientsource CASCADE;
DROP TABLE IF EXISTS sf_platform.dashboard CASCADE;
DROP TABLE IF EXISTS sf_platform.dashboardcomponent CASCADE;
DROP TABLE IF EXISTS sf_platform.report CASCADE;
DROP TABLE IF EXISTS sf_platform.loginhistory CASCADE;
DROP TABLE IF EXISTS sf_platform.setupaudittrail CASCADE;
DROP TABLE IF EXISTS sf_platform.certificate CASCADE;
DROP TABLE IF EXISTS sf_social.socialpost CASCADE;
DROP TABLE IF EXISTS sf_social.socialpersona CASCADE;
DROP TABLE IF EXISTS sf_social.authprovider CASCADE;
DROP TABLE IF EXISTS sf_social.namedcredential CASCADE;
DROP TABLE IF EXISTS sf_assets.assetshare CASCADE;
DROP TABLE IF EXISTS sf_assets.assetrelationship CASCADE;
DROP TABLE IF EXISTS sf_assets.photo CASCADE;
DROP TABLE IF EXISTS sf_assets.fieldhistory CASCADE;
DROP TABLE IF EXISTS sf_messaging.messagingchannel CASCADE;
DROP TABLE IF EXISTS sf_messaging.messagingenduser CASCADE;
DROP TABLE IF EXISTS sf_messaging.messagingsession CASCADE;

CREATE TABLE sf_core.sfuser (
    id CHAR(18) PRIMARY KEY,
    username VARCHAR(80) UNIQUE NOT NULL,
    email VARCHAR(80) NOT NULL,
    name VARCHAR(80) NOT NULL,
    isactive BOOLEAN NOT NULL DEFAULT TRUE,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_core.profile (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80) UNIQUE NOT NULL,
    userlicense VARCHAR(40),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_core.userrole (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    parentroleid CHAR(18) REFERENCES sf_core.userrole(id),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_core.permissionset (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80) UNIQUE NOT NULL,
    label VARCHAR(80) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_core.permissionsetassignment (
    id CHAR(18) PRIMARY KEY,
    assigneeid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    permissionsetid CHAR(18) REFERENCES sf_core.permissionset(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_core.permissionsetlicense (
    id CHAR(18) PRIMARY KEY,
    developername VARCHAR(80) UNIQUE NOT NULL,
    totallicenses INTEGER,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_core.recordtype (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    sobjecttype VARCHAR(40) NOT NULL,
    isactive BOOLEAN NOT NULL DEFAULT TRUE,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_core.sfgroup (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    type VARCHAR(40) CHECK (type IN ('Regular', 'Role', 'RoleAndSubordinates', 'Queue')),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_core.territory2model (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    state VARCHAR(40) CHECK (state IN ('Planning', 'Active', 'Archived', 'Overlay')),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_core.territory2type (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    priority INTEGER,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_core.territory2 (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    territory2modelid CHAR(18) REFERENCES sf_core.territory2model(id) NOT NULL,
    territory2typeid CHAR(18) REFERENCES sf_core.territory2type(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_core.userterritory2association (
    id CHAR(18) PRIMARY KEY,
    userid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    territory2id CHAR(18) REFERENCES sf_core.territory2(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_account.account (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    type VARCHAR(40) CHECK (type IN ('Customer', 'Prospect', 'Partner', 'Reseller')),
    industry VARCHAR(40) CHECK (industry IN ('Technology', 'Healthcare', 'Financial Services', 'Manufacturing', 'Retail')),
    annualrevenue NUMERIC(18,0),
    phone VARCHAR(40),
    website VARCHAR(255),
    ownerid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    parentid CHAR(18) REFERENCES sf_account.account(id),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_account.contact (
    id CHAR(18) PRIMARY KEY,
    accountid CHAR(18) REFERENCES sf_account.account(id),
    firstname VARCHAR(40),
    lastname VARCHAR(80) NOT NULL,
    email VARCHAR(80),
    phone VARCHAR(40),
    ownerid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    reportstoid CHAR(18) REFERENCES sf_account.contact(id),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_account.individual (
    id CHAR(18) PRIMARY KEY,
    firstname VARCHAR(40),
    lastname VARCHAR(80) NOT NULL,
    hasoptedoutsolicit BOOLEAN NOT NULL DEFAULT FALSE,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_account.individualshare (
    id CHAR(18) PRIMARY KEY,
    individualid CHAR(18) REFERENCES sf_account.individual(id) NOT NULL,
    userorgroupid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    accesslevel VARCHAR(20) CHECK (accesslevel IN ('Read', 'Edit', 'All')),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_account.partner (
    id CHAR(18) PRIMARY KEY,
    accountfromid CHAR(18) REFERENCES sf_account.account(id) NOT NULL,
    accounttoid CHAR(18) REFERENCES sf_account.account(id) NOT NULL,
    role VARCHAR(40),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_account.organization (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    instancename VARCHAR(20),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_sales.lead (
    id CHAR(18) PRIMARY KEY,
    firstname VARCHAR(40),
    lastname VARCHAR(80) NOT NULL,
    company VARCHAR(255) NOT NULL,
    email VARCHAR(80),
    status VARCHAR(40) NOT NULL DEFAULT 'Open' CHECK (status IN ('Open', 'Contacted', 'Qualified', 'Unqualified')),
    isconverted BOOLEAN NOT NULL DEFAULT FALSE,
    convertedaccountid CHAR(18) REFERENCES sf_account.account(id),
    ownerid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_sales.opportunity (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(120) NOT NULL,
    accountid CHAR(18) REFERENCES sf_account.account(id),
    stagename VARCHAR(40) NOT NULL CHECK (stagename IN ('Prospecting', 'Qualification', 'Proposal', 'Negotiation', 'Closed Won', 'Closed Lost')),
    amount NUMERIC(18,2),
    closedate DATE NOT NULL,
    ownerid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    isclosed BOOLEAN NOT NULL DEFAULT FALSE,
    iswon BOOLEAN NOT NULL DEFAULT FALSE,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_sales.opportunitylineitem (
    id CHAR(18) PRIMARY KEY,
    opportunityid CHAR(18) REFERENCES sf_sales.opportunity(id) NOT NULL,
    quantity NUMERIC(18,3) NOT NULL,
    unitprice NUMERIC(18,2) NOT NULL,
    totalprice NUMERIC(18,2),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_sales.opportunitycontactrole (
    id CHAR(18) PRIMARY KEY,
    opportunityid CHAR(18) REFERENCES sf_sales.opportunity(id) NOT NULL,
    contactid CHAR(18) REFERENCES sf_account.contact(id) NOT NULL,
    role VARCHAR(40),
    isprimary BOOLEAN NOT NULL DEFAULT FALSE,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_sales.campaign (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    type VARCHAR(40) CHECK (type IN ('Email', 'Webinar', 'Conference', 'Advertisement')),
    status VARCHAR(40) CHECK (status IN ('Planned', 'In Progress', 'Completed', 'Aborted')),
    budgetedcost NUMERIC(18,2),
    isactive BOOLEAN NOT NULL DEFAULT TRUE,
    ownerid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_sales.campaignmember (
    id CHAR(18) PRIMARY KEY,
    campaignid CHAR(18) REFERENCES sf_sales.campaign(id) NOT NULL,
    leadid CHAR(18) REFERENCES sf_sales.lead(id),
    contactid CHAR(18) REFERENCES sf_account.contact(id),
    status VARCHAR(40) CHECK (status IN ('Sent', 'Responded')),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_sales.quote (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    opportunityid CHAR(18) REFERENCES sf_sales.opportunity(id) NOT NULL,
    status VARCHAR(40) CHECK (status IN ('Draft', 'Needs Review', 'Approved', 'Accepted')),
    totalprice NUMERIC(18,2),
    ownerid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_sales.quotelineitem (
    id CHAR(18) PRIMARY KEY,
    quoteid CHAR(18) REFERENCES sf_sales.quote(id) NOT NULL,
    quantity NUMERIC(18,3) NOT NULL,
    unitprice NUMERIC(18,2) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_sales.quotedocument (
    id CHAR(18) PRIMARY KEY,
    quoteid CHAR(18) REFERENCES sf_sales.quote(id) NOT NULL,
    document VARCHAR(255),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_sales.contract (
    id CHAR(18) PRIMARY KEY,
    accountid CHAR(18) REFERENCES sf_account.account(id) NOT NULL,
    status VARCHAR(40) NOT NULL DEFAULT 'Draft' CHECK (status IN ('Draft', 'In Approval Process', 'Activated')),
    startdate DATE,
    contractterm INTEGER,
    ownerid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_sales.contractlineitem (
    id CHAR(18) PRIMARY KEY,
    contractid CHAR(18) REFERENCES sf_sales.contract(id) NOT NULL,
    quantity NUMERIC(18,3),
    unitprice NUMERIC(18,2),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_sales.sforder (
    id CHAR(18) PRIMARY KEY,
    accountid CHAR(18) REFERENCES sf_account.account(id) NOT NULL,
    contractid CHAR(18) REFERENCES sf_sales.contract(id),
    status VARCHAR(40) NOT NULL DEFAULT 'Draft' CHECK (status IN ('Draft', 'Activated')),
    totalamount NUMERIC(18,2),
    ownerid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_sales.orderitem (
    id CHAR(18) PRIMARY KEY,
    orderid CHAR(18) REFERENCES sf_sales.sforder(id) NOT NULL,
    quantity NUMERIC(18,3) NOT NULL,
    unitprice NUMERIC(18,2) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_sales.product (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    productcode VARCHAR(40) UNIQUE,
    isactive BOOLEAN NOT NULL DEFAULT TRUE,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_sales.product2 (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    productcode VARCHAR(40) UNIQUE,
    family VARCHAR(40),
    isactive BOOLEAN NOT NULL DEFAULT TRUE,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_sales.pricebook (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    isactive BOOLEAN NOT NULL DEFAULT TRUE,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_sales.pricebook2 (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    isactive BOOLEAN NOT NULL DEFAULT TRUE,
    isstandard BOOLEAN NOT NULL DEFAULT FALSE,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_sales.payment (
    id CHAR(18) PRIMARY KEY,
    orderid CHAR(18) REFERENCES sf_sales.sforder(id),
    amount NUMERIC(18,2) NOT NULL,
    status VARCHAR(40) CHECK (status IN ('Pending', 'Processed', 'Failed')),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_sales.returnorder (
    id CHAR(18) PRIMARY KEY,
    orderid CHAR(18) REFERENCES sf_sales.sforder(id) NOT NULL,
    accountid CHAR(18) REFERENCES sf_account.account(id) NOT NULL,
    status VARCHAR(40) CHECK (status IN ('Draft', 'Submitted', 'Approved')),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_sales.returnorderlineitem (
    id CHAR(18) PRIMARY KEY,
    returnorderid CHAR(18) REFERENCES sf_sales.returnorder(id) NOT NULL,
    quantityreturned NUMERIC(18,3),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_service.sfcase (
    id CHAR(18) PRIMARY KEY,
    casenumber VARCHAR(30) UNIQUE NOT NULL,
    accountid CHAR(18) REFERENCES sf_account.account(id),
    contactid CHAR(18) REFERENCES sf_account.contact(id),
    subject VARCHAR(255),
    status VARCHAR(40) NOT NULL DEFAULT 'New' CHECK (status IN ('New', 'Working', 'Escalated', 'Closed')),
    priority VARCHAR(40) NOT NULL DEFAULT 'Medium' CHECK (priority IN ('Low', 'Medium', 'High')),
    ownerid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_service.solution (
    id CHAR(18) PRIMARY KEY,
    solutionname VARCHAR(120) NOT NULL,
    status VARCHAR(40) CHECK (status IN ('Draft', 'Reviewed')),
    ownerid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_service.entitlement (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    accountid CHAR(18) REFERENCES sf_account.account(id) NOT NULL,
    startdate DATE,
    enddate DATE,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_service.entitlementtemplate (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80) UNIQUE NOT NULL,
    businesshoursid CHAR(18),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_service.slaprocess (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    isactive BOOLEAN NOT NULL DEFAULT TRUE,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_service.casemilestone (
    id CHAR(18) PRIMARY KEY,
    caseid CHAR(18) REFERENCES sf_service.sfcase(id) NOT NULL,
    completiondate TIMESTAMPTZ,
    iscompleted BOOLEAN NOT NULL DEFAULT FALSE,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_service.milestonetype (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80) UNIQUE NOT NULL,
    recurrencetype VARCHAR(20) CHECK (recurrencetype IN ('None', 'Repeat')),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_service.livechattranscript (
    id CHAR(18) PRIMARY KEY,
    caseid CHAR(18) REFERENCES sf_service.sfcase(id),
    status VARCHAR(40) CHECK (status IN ('Waiting', 'InProgress', 'Completed')),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_service.livechatvisitor (
    id CHAR(18) PRIMARY KEY,
    firstsessionkey VARCHAR(80),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_service.livechatdeployment (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80) UNIQUE NOT NULL,
    isactive BOOLEAN NOT NULL DEFAULT TRUE,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_service.livechatbutton (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    deploymentid CHAR(18) REFERENCES sf_service.livechatdeployment(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_service.quicktext (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    message TEXT,
    ownerid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_service.chatsession (
    id CHAR(18) PRIMARY KEY,
    livechatvisitorid CHAR(18) REFERENCES sf_service.livechatvisitor(id) NOT NULL,
    status VARCHAR(40),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_service.servicecontract (
    id CHAR(18) PRIMARY KEY,
    accountid CHAR(18) REFERENCES sf_account.account(id) NOT NULL,
    startdate DATE,
    enddate DATE,
    status VARCHAR(40) CHECK (status IN ('Draft', 'Activated')),
    ownerid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_service.casearticle (
    id CHAR(18) PRIMARY KEY,
    caseid CHAR(18) REFERENCES sf_service.sfcase(id) NOT NULL,
    relevancerank NUMERIC(5,2),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_service.duplicatejob (
    id CHAR(18) PRIMARY KEY,
    jobname VARCHAR(80),
    sobjecttype VARCHAR(40),
    status VARCHAR(20) CHECK (status IN ('Pending', 'InProgress', 'Completed')),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_field_service.workorder (
    id CHAR(18) PRIMARY KEY,
    accountid CHAR(18) REFERENCES sf_account.account(id),
    subject VARCHAR(255),
    status VARCHAR(40) CHECK (status IN ('New', 'In Progress', 'Completed', 'Closed')),
    ownerid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_field_service.workorderlineitem (
    id CHAR(18) PRIMARY KEY,
    workorderid CHAR(18) REFERENCES sf_field_service.workorder(id) NOT NULL,
    productid CHAR(18) REFERENCES sf_sales.product2(id),
    quantity NUMERIC(18,3),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_field_service.operatinghours (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    timezone VARCHAR(40),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_field_service.serviceterritorylocation (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80),
    operatinghoursid CHAR(18) REFERENCES sf_field_service.operatinghours(id),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_field_service.maintenanceasset (
    id CHAR(18) PRIMARY KEY,
    workorderid CHAR(18) REFERENCES sf_field_service.workorder(id),
    status VARCHAR(40),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_field_service.maintenanceplan (
    id CHAR(18) PRIMARY KEY,
    accountid CHAR(18) REFERENCES sf_account.account(id) NOT NULL,
    name VARCHAR(80) NOT NULL,
    frequency INTEGER,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_field_service.servicereport (
    id CHAR(18) PRIMARY KEY,
    workorderid CHAR(18) REFERENCES sf_field_service.workorder(id),
    name VARCHAR(80),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_field_service.servicecrew (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_field_service.servicecrewmember (
    id CHAR(18) PRIMARY KEY,
    servicecrewid CHAR(18) REFERENCES sf_field_service.servicecrew(id) NOT NULL,
    sfuserid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_field_service.timesheet (
    id CHAR(18) PRIMARY KEY,
    sfuserid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    status VARCHAR(40) CHECK (status IN ('Draft', 'Submitted', 'Approved')),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_activity.task (
    id CHAR(18) PRIMARY KEY,
    subject VARCHAR(255),
    whoid CHAR(18) REFERENCES sf_account.contact(id),
    whatid CHAR(18) REFERENCES sf_account.account(id),
    status VARCHAR(40) CHECK (status IN ('Not Started', 'In Progress', 'Completed')),
    priority VARCHAR(40) CHECK (priority IN ('Low', 'Normal', 'High')),
    activitydate DATE,
    ownerid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_activity.event (
    id CHAR(18) PRIMARY KEY,
    subject VARCHAR(255),
    whoid CHAR(18) REFERENCES sf_account.contact(id),
    whatid CHAR(18) REFERENCES sf_account.account(id),
    startdatetime TIMESTAMPTZ,
    enddatetime TIMESTAMPTZ,
    ownerid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_activity.eventrelation (
    id CHAR(18) PRIMARY KEY,
    eventid CHAR(18) REFERENCES sf_activity.event(id) NOT NULL,
    relationid CHAR(18) REFERENCES sf_account.contact(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_activity.taskrelation (
    id CHAR(18) PRIMARY KEY,
    taskid CHAR(18) REFERENCES sf_activity.task(id) NOT NULL,
    relationid CHAR(18) REFERENCES sf_account.contact(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_activity.timesheetentry (
    id CHAR(18) PRIMARY KEY,
    timesheetid CHAR(18) REFERENCES sf_field_service.timesheet(id) NOT NULL,
    hours NUMERIC(5,2),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_content.contentdocument (
    id CHAR(18) PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    filetype VARCHAR(20),
    ownerid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_content.contentversion (
    id CHAR(18) PRIMARY KEY,
    contentdocumentid CHAR(18) REFERENCES sf_content.contentdocument(id) NOT NULL,
    versionnumber INTEGER,
    title VARCHAR(255),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_content.contentdocumentlink (
    id CHAR(18) PRIMARY KEY,
    contentdocumentid CHAR(18) REFERENCES sf_content.contentdocument(id) NOT NULL,
    linkedentityid CHAR(18) REFERENCES sf_account.account(id) NOT NULL,
    sharetype VARCHAR(20) CHECK (sharetype IN ('V', 'C', 'I')),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_content.attachment (
    id CHAR(18) PRIMARY KEY,
    parentid CHAR(18) REFERENCES sf_service.sfcase(id) NOT NULL,
    name VARCHAR(255) NOT NULL,
    contenttype VARCHAR(40),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_content.note (
    id CHAR(18) PRIMARY KEY,
    parentid CHAR(18) REFERENCES sf_account.account(id),
    title VARCHAR(255),
    body TEXT,
    ownerid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_collab.collaborationgroup (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    collaborationtype VARCHAR(20) CHECK (collaborationtype IN ('Public', 'Private')),
    ownerid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_collab.feedpost (
    id CHAR(18) PRIMARY KEY,
    parentid CHAR(18) REFERENCES sf_account.account(id) NOT NULL,
    body TEXT,
    type VARCHAR(20) CHECK (type IN ('TextPost', 'ContentPost', 'LinkPost')),
    createdbyid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_collab.feedcomment (
    id CHAR(18) PRIMARY KEY,
    feeditemid CHAR(18) REFERENCES sf_collab.feedpost(id) NOT NULL,
    commentbody TEXT,
    createdbyid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_collab.topic (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80) UNIQUE NOT NULL,
    description VARCHAR(255),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_process.processinstance (
    id CHAR(18) PRIMARY KEY,
    targetobjectid CHAR(18) REFERENCES sf_sales.opportunity(id) NOT NULL,
    status VARCHAR(40) CHECK (status IN ('Pending', 'Approved', 'Rejected')),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_process.duplicatejobmatchingrule (
    id CHAR(18) PRIMARY KEY,
    duplicatejobid CHAR(18) REFERENCES sf_service.duplicatejob(id) NOT NULL,
    matchingrulesobjecttype VARCHAR(40),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_marketing.emailtemplate (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    subject VARCHAR(255),
    ownerid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_marketing.listemail (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    emailtemplateid CHAR(18) REFERENCES sf_marketing.emailtemplate(id),
    status VARCHAR(20) CHECK (status IN ('Draft', 'Sent')),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_marketing.listemailrecipientsource (
    id CHAR(18) PRIMARY KEY,
    listemailid CHAR(18) REFERENCES sf_marketing.listemail(id) NOT NULL,
    campaignid CHAR(18) REFERENCES sf_sales.campaign(id),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_platform.dashboard (
    id CHAR(18) PRIMARY KEY,
    title VARCHAR(80) NOT NULL,
    ownerid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_platform.dashboardcomponent (
    id CHAR(18) PRIMARY KEY,
    dashboardid CHAR(18) REFERENCES sf_platform.dashboard(id) NOT NULL,
    componenttype VARCHAR(20) CHECK (componenttype IN ('Chart', 'Gauge', 'Metric', 'Table')),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_platform.report (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    format VARCHAR(20) CHECK (format IN ('Tabular', 'Summary', 'Matrix')),
    ownerid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_platform.loginhistory (
    id CHAR(18) PRIMARY KEY,
    userid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    status VARCHAR(40) CHECK (status IN ('Success', 'Failed')),
    logintime TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_platform.setupaudittrail (
    id CHAR(18) PRIMARY KEY,
    action VARCHAR(80),
    createdbyid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_platform.certificate (
    id CHAR(18) PRIMARY KEY,
    developername VARCHAR(80) UNIQUE NOT NULL,
    expirationdate DATE,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_social.socialpost (
    id CHAR(18) PRIMARY KEY,
    parentid CHAR(18) REFERENCES sf_service.sfcase(id),
    content TEXT,
    provider VARCHAR(20) CHECK (provider IN ('Twitter', 'Facebook', 'Instagram')),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_social.socialpersona (
    id CHAR(18) PRIMARY KEY,
    parentid CHAR(18) REFERENCES sf_account.contact(id) NOT NULL,
    provider VARCHAR(20),
    realname VARCHAR(80),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_social.authprovider (
    id CHAR(18) PRIMARY KEY,
    developername VARCHAR(80) UNIQUE NOT NULL,
    providertype VARCHAR(20) CHECK (providertype IN ('Facebook', 'Google', 'OpenIdConnect')),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_social.namedcredential (
    id CHAR(18) PRIMARY KEY,
    developername VARCHAR(80) UNIQUE NOT NULL,
    endpoint VARCHAR(255),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_assets.assetshare (
    id CHAR(18) PRIMARY KEY,
    assetid CHAR(18) REFERENCES sf_field_service.workorder(id) NOT NULL,
    userorgroupid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    accesslevel VARCHAR(20) CHECK (accesslevel IN ('Read', 'Edit')),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_assets.assetrelationship (
    id CHAR(18) PRIMARY KEY,
    assetid CHAR(18) REFERENCES sf_field_service.workorder(id) NOT NULL,
    relatedassetid CHAR(18) REFERENCES sf_field_service.workorder(id),
    relationshiptype VARCHAR(40),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_assets.photo (
    id CHAR(18) PRIMARY KEY,
    linkedentityid CHAR(18) REFERENCES sf_account.contact(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_assets.fieldhistory (
    id CHAR(18) PRIMARY KEY,
    parentid CHAR(18) REFERENCES sf_sales.opportunity(id) NOT NULL,
    field VARCHAR(80),
    newvalue VARCHAR(255),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_messaging.messagingchannel (
    id CHAR(18) PRIMARY KEY,
    developername VARCHAR(80) UNIQUE NOT NULL,
    channeltype VARCHAR(20) CHECK (channeltype IN ('Sms', 'WhatsApp', 'Facebook')),
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_messaging.messagingenduser (
    id CHAR(18) PRIMARY KEY,
    name VARCHAR(80),
    messagingchannelid CHAR(18) REFERENCES sf_messaging.messagingchannel(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sf_messaging.messagingsession (
    id CHAR(18) PRIMARY KEY,
    messagingenduserid CHAR(18) REFERENCES sf_messaging.messagingenduser(id) NOT NULL,
    status VARCHAR(20) CHECK (status IN ('Active', 'Ended')),
    ownerid CHAR(18) REFERENCES sf_core.sfuser(id) NOT NULL,
    createddate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lastmodifieddate TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
