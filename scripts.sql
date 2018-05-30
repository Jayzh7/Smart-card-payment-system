create table FSS_RUN_TABLE
(runID NUMBER PRIMARY KEY,
 RunStart DATE NOT NULL,
 RunEnd DATE,
 Outcome VARCHAR2(15),
 Remarks VARCHAR2(255));
 
 DROP TABLE FSS_RUN_TABLE;
 
 DROP TABLE RUN_LOG;
 create table FSS_DAILY_TRANSACTIONS
 (TRANSACTIONNR NUMBER,
  DOWNLOADDATE DATE,
  TERMINALID VARCHAR2(10),
  CARDID VARCHAR2(17),
  TRANSACTIONDATE DATE,
  CARDOLDVALUE NUMBER,
  TRANSACTIONAMOUNT NUMBER,
  CARDNEWVALUE NUMBER,
  TRANSACTIONSTATUS VARCHAR2(1),
  ERRORCODE VARCHAR2(25),
  LODGEREF VARCHAR2(18)
);

DROP TABLE FSS_DAILY_TRANSACTIONS;

TRUNCATE table FSS_DAILY_TRANSACTIONS;
TRUNCATE table FSS_DAILY_SETTLEMENT;

create table FSS_DAILY_SETTLEMENT
(SETTLEDATE DATE,
 MERCHANTID NUMBER,
 MERCHANTNAME VARCHAR(50),
 LODGEREF VARCHAR2(18),
 TOTALAMOUNT NUMBER
);

TRUNCATE TABLE  FSS_DAILY_SETTLEMENT;
DROP TABLE FSS_DAILY_SETTLEMENT;

CREATE SEQUENCE seq_lodge_ref
START WITH 1
INCREMENT BY 1;

CREATE SEQUENCE seq_run_id
START WITH 1
INCREMENT BY 1;

DROP DIRECTORY MY_DIR;
CREATE DIRECTORY MY_DIR as '/exports/orcloz';

select * from FSS_TRANSACTIONS where trunc(downloaddate) = trunc(sysdate);

CREATE OR REPLACE TRIGGER tri_settlement_insert
BEFORE
INSERT ON FSS_DAILY_SETTLEMENT
FOR EACH ROW
BEGIN
--select to_char(:old.SETTLEDATE, 'MMDDYYYY') -- || LPAD(seq_lodge_ref.nextval, 10, '0'))
--into :new.lodgeref from dual;
:new.lodgeref := to_char(:old.SETTLEDATE, 'MMDDYYYY') || LPAD(seq_lodge_ref.nextval, 10, '0');
END tri_settlement_insert;

drop trigger tri_settlement_insert;
    