CREATE OR REPLACE PACKAGE BODY Pkg_FSS_Settlement
    
IS
    LENGTH_OF_LINE NUMBER:= 80;
    OUTCOME_FAIL VARCHAR2(15):= 'FAIL';
    OUTCOME_SUCCESS VARCHAR2(15):= 'SUCCESS';
    
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
            AND trunc(t.transactiondate) >= to_date(to_char(sysdate, 'YYYY-MM'), 'YYYY-MM')
            group by m.merchantid, m.merchantlastname
            having sum(t.transactionamount) > v_minimum ;
            
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
            
            -- Update the log to be successful
            update FSS_RUN_TABLE
            set RUNEND = sysdate, OUTCOME = OUTCOME_SUCCESS, REMARKS = REMARKS_SUCCESS
            where RUNID in 
                (select max(runid) from FSS_RUN_TABLE);
        end if;
        COMMIT;
    END;
    
    PROCEDURE CenterText(p_text IN VARCHAR2,
                         p_file IN utl_file.file_type) IS
        v_padding NUMBER:= (LENGTH_OF_LINE - LENGTH(p_text))/2;
    BEGIN
        utl_file.put_line(p_file, LPAD(' ', v_padding, ' ') || p_text || LPAD(' ', v_padding, ' '));
    END;
    
    PROCEDURE PrintHeader(p_file IN utl_file.file_type, p_date IN DATE) IS
    BEGIN
        CenterText('SMARTCARD SETTLEMENT SYSTEM', p_file);
        CenterText('DAILY DESKBANK SUMMARY', p_file);
        utl_file.put_line(p_file, 'Date ' || to_char(p_date, 'DD-Mon-YYYY'));
        utl_file.put_line(p_file, RPAD('Merchant ID', 14, ' ') ||  RPAD('Merchant Name', 31, ' ') || RPAD('Account Number', 18, ' ') || LPAD('Debit', 11, ' ') || LPAD('Credit', 10, ' '));
        utl_file.put_line(p_file, RPAD('-', 13, '-') || ' ' || RPAD('-', 30, '-') || ' ' || LPAD('-', 17, '-') || ' ' || LPAD('-', 10, '-') || ' ' ||  LPAD('-', 10, '-'));
    END;
    
    PROCEDURE PrintFooter(p_file IN utl_file.file_type,
                          p_name IN VARCHAR2) IS
    BEGIN
        utl_file.put_line(p_file, 'Deskbank file name : ' || p_name);
        utl_file.put_line(p_file, 'Dispatch Date      : ' || to_char(sysdate, 'DD Mon YYYY')); 
        utl_file.put_line(p_file, ' ');
        CenterText('*****  End of Report  *****', p_file);
    END;
    
    FUNCTION PrintMerchants(p_file IN utl_file.file_type,
                             p_date IN DATE)
    RETURN NUMBER 
    IS
        v_sum NUMBER:=0;
        CURSOR c_merchants IS
            SELECT s.TOTALAMOUNT, s.MERCHANTID, m.MERCHANTLASTNAME, m.MERCHANTBANKBSB, m.MERCHANTBANKACCNR FROM FSS_DAILY_SETTLEMENT s JOIN FSS_MERCHANT m on s.MERCHANTID = m.MERCHANTID WHERE trunc(s.SETTLEDATE) = trunc(p_date);
    BEGIN
        for r_merchants in c_merchants LOOP
            utl_file.put_line(p_file, RPAD(r_merchants.MERCHANTID, 13, ' ') || ' ' || RPAD(r_merchants.MERCHANTLASTNAME, 31, ' ')
            || ' ' || RPAD(substr(r_merchants.MERCHANTBANKBSB, 0, 3) || '-' || substr(r_merchants.MERCHANTBANKBSB, 3, 3) || 
                     r_merchants.MERCHANTBANKACCNR, 16, ' ') || RPAD(' ', 11, ' ') || LPAD(r_merchants.TOTALAMOUNT, 10, ' '));
            v_sum := v_sum + r_merchants.TOTALAMOUNT;
        end loop;
        return v_sum;
    END;
    
    PROCEDURE PrintSum(p_file in utl_file.file_type,
                       p_sum  in NUMBER)
    IS
        v_orgtitle VARCHAR2(15);
        v_accnr    VARCHAR2(20);
    BEGIN
        select ORGACCOUNTTITLE into v_orgtitle from FSS_ORGANISATION;
        select substr(ORGBSBNR, 0, 3) || '-' || substr(ORGBSBNR, 3, 3) || ORGBANKACCOUNT into v_accnr from FSS_ORGANISATION;
            
        utl_file.put_line(p_file, RPAD(' ', 13, ' ') || ' ' || RPAD(v_orgtitle, 31, ' ')
            || ' ' || RPAD(v_accnr, 16, ' ') || LPAD(p_sum, 11, ' ') || LPAD(' ', 10, ' '));
        utl_file.put_line(p_file, RPAD(' ', 13, ' ') || ' ' || RPAD(' ', 31, ' ')
            || ' ' || RPAD(' ', 16, ' ') || LPAD(' ', 11, '-') || RPAD(' ', 10, '-'));
        utl_file.put_line(p_file, RPAD('BALANCE TOTAL', 13, ' ') || ' ' || RPAD(' ', 31, ' ')
            || ' ' || RPAD(' ', 16, ' ') || LPAD(p_sum, 11, ' ') || LPAD(p_sum, 10, ' '));
    END;
 
    
    PROCEDURE DailySettlement IS
    BEGIN
        -- FIRST, insert transactions that have not been loaded into FSS_DAILY_TRANSACRIONS
        InsertTransactions;
        
        -- SECOND, settle transactions for today and update LOGREF
        SettleTransactions;
        
        -- THIRD, settle transactions for last month and update LOGREF
        -- SettleLastMonthTransactions;
    END;

    PROCEDURE DailyBankingSummary(p_date IN DATE default sysdate) IS
        v_file_name VARCHAR2(50);
        v_file utl_file.file_type;
        v_date DATE;
        
        v_sum NUMBER;
    BEGIN
        v_date :=to_date(p_date, 'DD-MON-YYYY');
        v_file_name := '13029285_DSREP_' || to_char(v_date, 'DDMMYYYY') || '.rpt';
        v_file := utl_file.fopen('ZJ_DIR', v_file_name, 'W');
        
        PrintHeader(v_file, v_date);
        v_sum := PrintMerchants(v_file, v_date);
        
        PrintSum(v_file, v_sum);
        PrintFooter(v_file, v_file_name);
        utl_file.fclose(v_file);
    END;
    
--    PROCEDURE FraudReport IS
--    BEGIN
--        
--    END;
        
END Pkg_FSS_Settlement;