    CREATE OR REPLACE PROCEDURE SettleTransactions IS
--        -- This cursor is used to identify unsettled transaction dates
--        CURSOR c_dat IS
--            select downloaddate from FSS_DAILY_SETTLEMENT
--            where 
--    
        -- This cursor is used to assign a lodgement reference number to each settlement
        CURSOR c_lod IS 
            select SETTLEDATE, MERCHANTID, LODGEREF from FSS_DAILY_SETTLEMENT s
            where s.LODGEREF IS NULL
            for update of s.lodgeref, s.settledate;
    BEGIN
        -- Settle eligible transactions that has not been settled
        insert into FSS_DAILY_SETTLEMENT (MERCHANTID, MERCHANTNAME, TOTALAMOUNT)
        select m.merchantid, m.merchantlastname, sum(t.transactionamount)
        from fss_daily_transactions t join fss_terminal ter on t.TERMINALID = ter.TERMINALID
        join fss_merchant m on ter.MERCHANTID = m.merchantid
        where t.lodgeref IS NULL
        AND trunc(t.transactiondate) >= to_date(to_char(sysdate, 'YYYY-MM'), 'YYYY-MM')
--        and trunc(t.downloaddate) IN (
--            select distinct trunc(DOWNLOADDATE) from FSS_DAILY_TRANSACTIONS transactions
--            where transactions.lodgeref IS NULL
--        )
        group by m.merchantid, m.merchantlastname --, trunc(t.downloaddate)
        having sum(t.transactionamount) > 7.75 ;-- trunc(t.transactiondate) < to_date(to_char(sysdate, 'YYYY-MM'), 'YYYY-MM');
        
        COMMIT;    
        
        for r_lod in c_lod LOOP
            -- Update a lodge reference number for each settlement
            update FSS_DAILY_SETTLEMENT    
            SET LODGEREF = to_char(sysdate, 'MMDDYYYY') || LPAD(seq_lodge_ref.nextval, 10, '0'),
            SETTLEDATE = trunc(sysdate)
            where CURRENT OF c_lod;

            -- Update a lodge reference number for settled transactions
            update fss_daily_transactions trans
            set trans.lodgeref = to_char(sysdate, 'MMDDYYYY') || LPAD(seq_lodge_ref.currval, 10, '0')
            where trans.TERMINALID IN (
                SELECT t.terminalid
                from fss_terminal t join fss_merchant m on t.merchantid = m.merchantid
                where m.merchantid = r_lod.merchantid)
            AND trunc(trans.transactiondate) >= to_date(to_char(sysdate, 'YYYY-MM'), 'YYYY-MM')
            AND trans.lodgeref IS NULL;
            
        END LOOP;
        COMMIT;
    END;
 
 
  CREATE OR REPLACE PROCEDURE InsertTransactions IS
    BEGIN
        insert into FSS_DAILY_TRANSACTIONS (TRANSACTIONNR, DOWNLOADDATE, TERMINALID, CARDID, TRANSACTIONDATE,
            CARDOLDVALUE, TRANSACTIONAMOUNT, CARDNEWVALUE, TRANSACTIONSTATUS, ERRORCODE)
            select TRANSACTIONNR, DOWNLOADDATE, TERMINALID, CARDID, TRANSACTIONDATE,
            CARDOLDVALUE, TRANSACTIONAMOUNT, CARDNEWVALUE, TRANSACTIONSTATUS, ERRORCODE
            from FSS_TRANSACTIONS 
            where not exists (select 1 from FSS_DAILY_TRANSACTIONS t2 where FSS_TRANSACTIONS.transactionnr = t2.transactionnr);
        COMMIT;
    END;
    
    
set serveroutput on;
begin
InsertTransactions;
SettleTransactions;
end;