create or replace procedure DailyBankingSummary(p_date IN VARCHAR)
IS
--
v_sum number;
cursor c_merchant is select distinct me.merchantid d_id, me.merchantaccounttitle title
from fss_transactions tr, fss_terminal te, fss_merchant me
where tr.terminalid = te.terminalid
and   te.merchantid = me.merchantid;
--
begin
    insert into FSS_DAILY_TRANSACTION (TRANSACTIONNR, DOWNLOADDATE, TERMINALID, CARDID, TRANSACTIONDATE,
            CARDOLDVALUE, TRANSACTIONAMOUNT, CARDNEWVALUE, TRANSACTIONSTATUS, ERRORCODE)
    select TRANSACTIONNR, DOWNLOADDATE, TERMINALID, CARDID, TRANSACTIONDATE,
            CARDOLDVALUE, TRANSACTIONAMOUNT, CARDNEWVALUE, TRANSACTIONSTATUS, ERRORCODE
            from FSS_TRANSACTIONS 
            where not exists (select 1 from FSS_DAILY_TRANSACTION t2 where FSS_TRANSACTIONS.transactionnr = t2.transactionnr)
            ;--AND to_char(trunc(TRANSACTIONDATE), 'dd-mm-yyyy') = to_char(to_date(p_date, 'DD-MON-YYYY'), 'dd-mm-yyyy');
    COMMIT;
    
    for r_merchant in c_merchant loop
        dbms_output.put_line(f_sum_merchant(r_merchant.d_id, p_date));
    end loop;
    
end;



begin
dailybankingsummary('04-Apr-2018');
end;