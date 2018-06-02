CREATE OR REPLACE PACKAGE BODY Pkg_FSS_Settlement
    
IS
    LENGTH_OF_LINE NUMBER:= 80;
    OUTCOME_FAIL VARCHAR2(15):= 'FAIL';
    OUTCOME_SUCCESS VARCHAR2(15):= 'SUCCESS';
    
    RECORD_TYPE VARCHAR2(1) := '1';
    FOOTER_TYPE VARCHAR2(1) := '7';
    FOOTER_FILLER VARCHAR(7) := '999-999';
    
    DEBIT_CODE  VARCHAR2(2) := '13';
    CREDIT_CODE VARCHAR2(2) := '50';
    
    REMARKS_FAIL VARCHAR2(40) := 'Already settled earlier today';
    REMARKS_SUCCESS VARCHAR2(40) := 'Successfully Settled';
    
    FUNCTION f_sum_merchant(p_merchantID in FSS_MERCHANT.merchantid%type, p_date in varchar)
    return number
    is
    --
    v_sum number:= 0;
    --
    begin
        select sum(tr.transactionamount)  into v_sum from FSS_DAILY_TRANSACTIONS tr , FSS_TERMINAL te, FSS_MERCHANT me
        where tr.terminalid = te.terminalid
        and te.merchantid = me.merchantid
        and trunc(tr.TRANSACTIONDATE) = trunc(to_date(p_date, 'DD-MON-YYYY'))
        and me.merchantid = p_merchantid;
        return v_sum;
    end;
    
    PROCEDURE InsertTransactions IS
    BEGIN
        insert into FSS_DAILY_TRANSACTIONS (TRANSACTIONNR, DOWNLOADDATE, TERMINALID, CARDID, TRANSACTIONDATE,
            CARDOLDVALUE, TRANSACTIONAMOUNT, CARDNEWVALUE, TRANSACTIONSTATUS, ERRORCODE)
            select TRANSACTIONNR, DOWNLOADDATE, TERMINALID, CARDID, TRANSACTIONDATE,
            CARDOLDVALUE, TRANSACTIONAMOUNT, CARDNEWVALUE, TRANSACTIONSTATUS, ERRORCODE
            from FSS_TRANSACTIONS 
            where not exists (select 1 from FSS_DAILY_TRANSACTIONS t2 where FSS_TRANSACTIONS.transactionnr = t2.transactionnr);
        
        COMMIT;
    END;
    
    PROCEDURE SettleTransactions IS
        -- This cursor is used to assign a lodgement reference number to each settlement
        v_runTimes NUMBER;
        v_minimum NUMBER;
        CURSOR c_lod IS 
            select SETTLEDATE, MERCHANTID, LODGEREF from FSS_DAILY_SETTLEMENT s
            where s.LODGEREF IS NULL
            for update of s.lodgeref, s.settledate;
    BEGIN
        -- Check run table
        select count(*) into v_runTimes from FSS_RUN_TABLE where trunc(RUNEND) = trunc(sysdate) and OUTCOME=OUTCOME_SUCCESS;
        
        if v_runTimes >= 1 then
            insert into FSS_RUN_TABLE (RUNID, RUNSTART, RUNEND, OUTCOME, REMARKS)
            values(seq_run_id.nextval, sysdate, sysdate, OUTCOME_FAIL, REMARKS_FAIL);
        else
            -- Insert fail log first, update later
            insert into FSS_RUN_TABLE (RUNID, RUNSTART, OUTCOME, REMARKS)
            values(seq_run_id.nextval, sysdate, OUTCOME_FAIL, REMARKS_FAIL);
            
            -- Set minimum amount to be settled
            if trunc(sysdate) = LAST_DAY(sysdate) then
                v_minimum := 0;
            else
                select referencevalue into v_minimum from FSS_REFERENCE where referenceid = 'DMIN';
            end if;
            
            -- Settle eligible transactions that has not been settled
            insert into FSS_DAILY_SETTLEMENT (MERCHANTID, MERCHANTNAME, TOTALAMOUNT)
            select m.merchantid, m.merchantlastname, sum(t.transactionamount)
            from fss_daily_transactions t join fss_terminal ter on t.TERMINALID = ter.TERMINALID
            join fss_merchant m on ter.MERCHANTID = m.merchantid
            where t.lodgeref IS NULL
--            AND trunc(t.transactiondate) >= to_date(to_char(sysdate, 'YYYY-MM'), 'YYYY-MM')
            group by m.merchantid, m.merchantlastname
            having sum(t.transactionamount) > v_minimum ;
            
            COMMIT;    
            
            for r_lod in c_lod LOOP
                -- Update a lodge reference number for each settlement
                update FSS_DAILY_SETTLEMENT    
                SET LODGEREF = to_char(sysdate, 'MMDDYYYY') || LPAD(seq_lodge_ref.nextval, 7, '0'),
                SETTLEDATE = trunc(sysdate)
                where CURRENT OF c_lod;
    
                -- Update a lodge reference number for settled transactions
                update fss_daily_transactions trans
                set trans.lodgeref = to_char(sysdate, 'MMDDYYYY') || LPAD(seq_lodge_ref.currval, 7, '0')
                where trans.TERMINALID IN (
                    SELECT t.terminalid
                    from fss_terminal t join fss_merchant m on t.merchantid = m.merchantid
                    where m.merchantid = r_lod.merchantid)
--                AND trunc(trans.transactiondate) >= to_date(to_char(sysdate, 'YYYY-MM'), 'YYYY-MM')
                AND trans.lodgeref IS NULL;
                
            END LOOP;
            
            -- Update the log to be successful
            update FSS_RUN_TABLE
            set RUNEND = sysdate, OUTCOME = OUTCOME_SUCCESS, REMARKS = REMARKS_SUCCESS
            where RUNID in 
                (select max(runid) from FSS_RUN_TABLE);
        end if;
        COMMIT;
    END;
    
    FUNCTION CenterText(p_text IN VARCHAR2)
    RETURN VARCHAR2
    IS
        v_padding NUMBER:= (LENGTH_OF_LINE - LENGTH(p_text))/2;
        v_return VARCHAR2(100):='';
    BEGIN
        v_return := LPAD(' ', v_padding, ' ') || p_text || LPAD(' ', v_padding, ' ');
        return v_return;
    END;
    
    FUNCTION PrintHeader(p_date IN DATE) 
    RETURN VARCHAR2
    IS
        v_return VARCHAR2(1000) := '';
    BEGIN
        v_return := v_return || CenterText('SMARTCARD SETTLEMENT SYSTEM') || CHR(10);
        v_return := v_return || CenterText('DAILY DESKBANK SUMMARY') || CHR(10);
        v_return := v_return || 'Date ' || to_char(p_date, 'DD-Mon-YYYY') || CHR(10);
        v_return := v_return || RPAD('Merchant ID', 14, ' ') ||  RPAD('Merchant Name', 31, ' ') || 
                                RPAD('Account Number', 18, ' ') || LPAD('Debit', 11, ' ') || LPAD('Credit', 10, ' ') || CHR(10);
        v_return := v_return || RPAD('-', 13, '-') || ' ' || RPAD('-', 30, '-') || ' ' || LPAD('-', 17, '-') || ' ' ||
                                LPAD('-', 10, '-') || ' ' ||  LPAD('-', 10, '-') || CHR(10);
        
        return v_return;
    END;
    
    FUNCTION PrintFooter(p_name IN VARCHAR2) 
    RETURN VARCHAR2 
    IS
        v_return VARCHAR2(1000) := '';
    BEGIN
        v_return := v_return || 'Deskbank file name : ' || p_name || CHR(10);
        v_return := v_return || 'Dispatch Date      : ' || to_char(sysdate, 'DD Mon YYYY') || CHR(10) || CHR(10);
        v_return := v_return || CenterText('*****  End of Report  *****');
        
        return v_return;
    END;
    
    FUNCTION PrintSum(p_sum  in NUMBER)
    return VARCHAR2
    IS
        v_orgtitle VARCHAR2(15);
        v_accnr    VARCHAR2(20);
        v_return   VARCHAR2(1000):= '';
    BEGIN
        select ORGACCOUNTTITLE into v_orgtitle from FSS_ORGANISATION;
        select substr(ORGBSBNR, 0, 3) || '-' || substr(ORGBSBNR, 3, 3) || ORGBANKACCOUNT into v_accnr from FSS_ORGANISATION;
            
        v_return := v_return || RPAD(' ', 13, ' ') || ' ' || RPAD(v_orgtitle, 31, ' ')
            || ' ' || RPAD(v_accnr, 16, ' ') || LPAD(p_sum, 11, ' ') || LPAD(' ', 10, ' ') || CHR(10);
        v_return := v_return || RPAD(' ', 13, ' ') || ' ' || RPAD(' ', 31, ' ')
            || ' ' || RPAD(' ', 16, ' ') || LPAD(' ', 11, '-') || RPAD(' ', 10, '-') || CHR(10);
        v_return := v_return || RPAD('BALANCE TOTAL', 13, ' ') || ' ' || RPAD(' ', 31, ' ')
            || ' ' || RPAD(' ', 16, ' ') || LPAD(p_sum, 11, ' ') || LPAD(p_sum, 10, ' ') || CHR(10);
            
        return v_return;
    END;
    PROCEDURE DeskbankFile(p_date IN DATE)
    IS
        v_print VARCHAR2(4000):= '';
        v_sum   NUMBER:= 0;
        v_cnt   NUMBER:= 0;
        v_file_name VARCHAR2(50);
        v_file utl_file.file_type;
        CURSOR c_merchants IS
            SELECT s.TOTALAMOUNT, s.MERCHANTID, m.MERCHANTACCOUNTTITLE, m.MERCHANTBANKBSB, m.MERCHANTBANKACCNR, s.LODGEREF
            FROM FSS_DAILY_SETTLEMENT s JOIN FSS_MERCHANT m on s.MERCHANTID = m.MERCHANTID 
            WHERE trunc(s.SETTLEDATE) = trunc(p_date);
    BEGIN
        v_file_name := '13029285' || '_DS_' || to_char(p_date, 'DDMMYYYY') || '.dat';
        v_file := utl_file.fopen('ZJ_DIR', v_file_name, 'W');
        -- Header
        v_print := '0' || RPAD(' ', 17, ' ') || '01WBC' || RPAD(' ', 7, ' ') || RPAD('S/CARD BUS PAYMENTS', 26, ' ') 
                       || '038759' || RPAD('INVOICES', 12, ' ') || RPAD(to_char(p_date, 'DDMMYY'), 6, ' ') || CHR(10);
        for r_merchants in c_merchants LOOP
            v_print := v_print || RECORD_TYPE;
            v_print := v_print || substr(r_merchants.MERCHANTBANKBSB, 0, 3) || '-' || substr(r_merchants.MERCHANTBANKBSB, 3, 3) || 
                     r_merchants.MERCHANTBANKACCNR;
            v_print := v_print || ' ' || DEBIT_CODE || LPAD(TO_CHAR(r_merchants.TOTALAMOUNT*100), 10, '0');
            v_print := v_print || RPAD(r_merchants.MERCHANTACCOUNTTITLE, 32, ' ');
            v_print := v_print || RPAD('F', 3, ' ');
            v_print := v_print || RPAD(r_merchants.LODGEREF, 15, ' ');
            v_print := v_print || '032-797   001005';
            v_print := v_print || 'SMARTCARD TRANS   ';
            v_print := v_print || LPAD('0', 8, '0');
            v_print := v_print || CHR(10);
            v_cnt := v_cnt + 1;
            v_sum := v_sum + r_merchants.TOTALAMOUNT;
        end loop;
        
        v_print := v_print || FOOTER_TYPE || FOOTER_FILLER || LPAD(' ', 12, ' ');
        v_print := v_print || LPAD('0', 10, '0') || LPAD(TO_CHAR(v_sum), 10, '0') || LPAD(TO_CHAR(v_sum), 10, '0');
        v_print := v_print || LPAD(' ', 24, ' ') || LPAD(TO_CHAR(v_cnt), 6, '0');
        
        utl_file.put_line(v_file, v_print);
        utl_file.fclose(v_file);
    END;
 
    
    PROCEDURE DailySettlement IS
    BEGIN
        -- FIRST, insert transactions that have not been loaded into FSS_DAILY_TRANSACRIONS
        InsertTransactions;
        
        -- SECOND, settle transactions for today and update LOGREF
        SettleTransactions;
  
        -- THIRD, settle transactions for last month and update LOGREF
--         SettleLastMonthTransactions;
    END;

    PROCEDURE DailyBankingSummary(p_date IN DATE default sysdate) IS
        v_file_name VARCHAR2(50);
        v_file utl_file.file_type;
        v_print VARCHAR2(4000);
        v_sum NUMBER:=0;
        CURSOR c_merchants IS
            SELECT s.TOTALAMOUNT, s.MERCHANTID, m.MERCHANTLASTNAME, m.MERCHANTBANKBSB, m.MERCHANTBANKACCNR 
            FROM FSS_DAILY_SETTLEMENT s JOIN FSS_MERCHANT m on s.MERCHANTID = m.MERCHANTID 
            WHERE trunc(s.SETTLEDATE) = trunc(p_date);
    BEGIN
        v_file_name := '13029285_DSREP_' || to_char(p_date, 'DDMMYYYY') || '.rpt';
        v_file := utl_file.fopen('ZJ_DIR', v_file_name, 'W');
        
        v_print := v_print || PrintHeader(p_date);
--        v_sum := PrintMerchants(v_file, p_date);
        for r_merchants in c_merchants LOOP
            v_print := v_print ||  RPAD(r_merchants.MERCHANTID, 13, ' ') || ' ' || RPAD(r_merchants.MERCHANTLASTNAME, 31, ' ')
            || ' ' || RPAD(substr(r_merchants.MERCHANTBANKBSB, 0, 3) || '-' || substr(r_merchants.MERCHANTBANKBSB, 3, 3) || 
                     r_merchants.MERCHANTBANKACCNR, 16, ' ') || RPAD(' ', 11, ' ') || LPAD(r_merchants.TOTALAMOUNT, 10, ' ') || CHR(10);
            v_sum := v_sum + r_merchants.TOTALAMOUNT;
        end loop;
        
        v_print := v_print || PrintSum(v_sum);
        v_print := v_print || PrintFooter(v_file_name);
        
        utl_file.put_line(v_file, v_print);
        
        DeskbankFile(p_date);
        utl_file.fclose(v_file);
    END;

    PROCEDURE FRAUDREPORT
    IS
    v_previous NUMBER:=-1;
    cursor c_cardid is 
        select distinct cardid from FSS_DAILY_TRANSACTIONS;
    cursor c_payments(p_cardid VARCHAR2) is
        select * from FSS_DAILY_TRANSACTIONS where cardid=p_cardid order by transactiondate ASC;
    BEGIN
        for r_cardid in c_cardid loop
            v_previous := -1;
            for r_payments in c_payments(r_cardid.cardid) loop
                if v_previous != -1 then
                    if r_payments.cardoldvalue != v_previous then
                        -- report fraud
                        INSERT INTO FSS_ABNORMAL_ACCOUNTS (TRANSACTIONNR)
                        VALUES(r_payments.TRANSACTIONNR);
                        COMMIT;
                    end if;
                    if r_payments.cardoldvalue - r_payments.transactionamount != r_payments.cardnewvalue then
                        -- report fraud
                        INSERT INTO FSS_ABNORMAL_TRANSACTIONS (TRANSACTIONNR)
                        VALUES(r_payments.TRANSACTIONNR);
                        COMMIT;
                    end if;
                end if;
                v_previous := r_payments.cardnewvalue;
            end loop;
        end loop;
    END;
    
        
END Pkg_FSS_Settlement;