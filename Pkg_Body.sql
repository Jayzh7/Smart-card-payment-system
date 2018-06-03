CREATE OR REPLACE PACKAGE BODY Pkg_FSS_Settlement
    
IS
    EMAIL_TO VARCHAR2(50) := 'jayzh7@hotmail.com';
    EMAIL_FROM VARCHAR2(50) := 'procedure@uts.edu.au';
    EMAIL_SUBJECT VARCHAR2(50) := 'Settlement reports';
    EMAIL_TEXT_MSG VARCHAR2(200) := 'Sent From the OMS Database by the PL/SQL application' || CHR(10) ||
                                    'The report data is in the attached files' || CHR(10) || CHR(10) ||
                                    'Regards' || CHR(10) ||
                                    'The OMS Database' || CHR(10);
                                    
    EMAIL_BS_NAME VARCHAR2(50) := 'Daily Banking Summary-';
    EMAIL_DF_NAME VARCHAR2(50) := 'Deskbank File-';
    EMAIL_SUFFIX VARCHAR2(10)  := '.txt';
    
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
    
    procedure send_email(  p_to            IN VARCHAR2,
                           p_from          IN VARCHAR2,
                           p_subject       IN VARCHAR2,
                           p_text_msg      IN VARCHAR2,
                           p_attach_name_1 IN VARCHAR2,
                           p_attach_msg_1  IN VARCHAR2,
                           p_attach_name_2 IN VARCHAR2,
                           p_attach_msg_2  IN VARCHAR2)
    as
    v_mailhost VARCHAR2(50) := 'postoffice.uts.edu.au';
    v_boundary VARCHAR2(50) := 'MY BOUNDARY';
    
    mail_conn       UTL_SMTP.connection;
    v_proc_name  VARCHAR2(50) := 'send_email';
    v_recipient_list  VARCHAR2(2000);
    v_recipient   VARCHAR2(80);
    v_counter     NUMBER := 0;
    con_nl VARCHAR2(2) := CHR(13)||CHR(10);
    con_email_footer VARCHAR2(250) := 'This is the email footer';
    --
    procedure log(p_message VARCHAR2) is
    BEGIN
        DBMS_OUTPUT.PUT_LINE(p_message);
    END;
    --
    --
    BEGIN
    --     v_recipient_list := REPLACE(p_recipient, ' ');  --get rid of any spaces so that it's easier to split up
    mail_conn := UTL_SMTP.open_connection (v_mailhost, 25);
    UTL_SMTP.helo (mail_conn, v_mailhost);
    UTL_SMTP.mail (mail_conn, p_from);
    UTL_SMTP.rcpt (mail_conn, p_to);
    UTL_SMTP.open_data (mail_conn);
    --         
    UTL_SMTP.write_data(mail_conn, 'From' || ':' || p_from || con_nl);
    UTL_SMTP.write_data(mail_conn, 'To'   || ':' || p_to   || con_nl);
    UTL_SMTP.write_data(mail_conn, 'Subject:'    || p_subject || con_nl);
    UTL_SMTP.write_data(mail_conn, 'MIME-Version: 1.0' || con_nl);
    UTL_SMTP.write_data(mail_conn, 'Content-Type: multipart/mixed; boundary="' || v_boundary || '"' || con_nl);
    
    if p_text_msg IS NOT NULL
    then
    UTL_SMTP.write_data(mail_conn, '--' || v_boundary || con_nl);
    UTL_SMTP.write_data(mail_conn, 'Content-Type: text/plain; charset="us-ascii"' || con_nl || con_nl);
    
    UTL_SMTP.write_data(mail_conn, p_text_msg || con_nl || con_nl);
    end if;
    
    if p_attach_name_2 IS NOT NULL 
    then
        if p_attach_msg_2 IS NOT NULL
        then 
            UTL_SMTP.write_data(mail_conn, con_nl || '--' || v_boundary || con_nl);
            UTL_SMTP.write_data(mail_conn, 'Content-Type: application/octet-stream; name="' || p_attach_name_2 || '"' || con_nl);
            UTL_SMTP.write_data(mail_conn, 'Content-Transfer-Encoding: 7bit' || con_nl || con_nl);
            UTL_SMTP.write_data(mail_conn, p_attach_msg_2 || con_nl || con_nl);
        --                
        --                UTL_SMTP.write_data(mail_conn, '--' || v_boundary || con_nl);
        end if;
    end if;
        
    if p_attach_name_1 IS NOT NULL 
    then
        if p_attach_msg_1 IS NOT NULL
        then 
            UTL_SMTP.write_data(mail_conn, '--' || v_boundary || con_nl);
            UTL_SMTP.write_data(mail_conn, 'Content-Type: application/octet-stream; name="' || p_attach_name_1 || '"' || con_nl);
            UTL_SMTP.write_data(mail_conn, 'Content-Transfer-Encoding: 7bit' || con_nl || con_nl);
            UTL_SMTP.write_data(mail_conn, p_attach_msg_1 || con_nl || con_nl);
        --                
            UTL_SMTP.write_data(mail_conn, '--' || v_boundary || '--' || con_nl);
        end if;
    end if;
    
    UTL_SMTP.close_data (mail_conn);
    UTL_SMTP.quit (mail_conn);
    log('Email sent, check your inbox');
    EXCEPTION
       WHEN OTHERS THEN
          log('Error occured in send_email with '||con_nl||SQLERRM);
          UTL_SMTP.close_data (mail_conn);
    END;

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
    
    FUNCTION PrintSummary(p_date IN DATE,
                          p_file_name IN VARCHAR2)
    RETURN VARCHAR2
    IS
        v_print VARCHAR2(4000);
        v_sum NUMBER:=0;
        CURSOR c_merchants IS
            SELECT s.TOTALAMOUNT, s.MERCHANTID, m.MERCHANTLASTNAME, m.MERCHANTBANKBSB, m.MERCHANTBANKACCNR 
            FROM FSS_DAILY_SETTLEMENT s JOIN FSS_MERCHANT m on s.MERCHANTID = m.MERCHANTID 
            WHERE trunc(s.SETTLEDATE) = trunc(p_date);
    BEGIN
        v_print := v_print || PrintHeader(p_date);
        
        for r_merchants in c_merchants LOOP
            v_print := v_print ||  RPAD(r_merchants.MERCHANTID, 13, ' ') || ' ' || RPAD(r_merchants.MERCHANTLASTNAME, 31, ' ')
            || ' ' || RPAD(substr(r_merchants.MERCHANTBANKBSB, 0, 3) || '-' || substr(r_merchants.MERCHANTBANKBSB, 3, 3) || 
                     r_merchants.MERCHANTBANKACCNR, 16, ' ') || RPAD(' ', 11, ' ') || LPAD(r_merchants.TOTALAMOUNT, 10, ' ') || CHR(10);
            v_sum := v_sum + r_merchants.TOTALAMOUNT;
        end loop;
        
        v_print := v_print || PrintSum(v_sum);
        v_print := v_print || PrintFooter(p_file_name);
        
        return v_print;
    END;
    
    --TODO insert credit record
    FUNCTION PrintDeskbankFile(p_date IN DATE)
    RETURN VARCHAR2
    IS
        v_print VARCHAR2(4000):= '';
        v_sum   NUMBER:= 0;
        v_cnt   NUMBER:= 0;
        CURSOR c_merchants IS
                SELECT s.TOTALAMOUNT, s.MERCHANTID, m.MERCHANTACCOUNTTITLE, m.MERCHANTBANKBSB, m.MERCHANTBANKACCNR, s.LODGEREF
                FROM FSS_DAILY_SETTLEMENT s JOIN FSS_MERCHANT m on s.MERCHANTID = m.MERCHANTID 
                WHERE trunc(s.SETTLEDATE) = trunc(p_date);
    BEGIN
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
        
        return v_print;
    END;
    
    PROCEDURE DeskbankFile(p_date IN DATE)
    IS
        v_file_name VARCHAR2(50);
        v_file utl_file.file_type;
    BEGIN
        v_file_name := '13029285' || '_DS_' || to_char(p_date, 'DDMMYYYY') || '.dat';
        v_file := utl_file.fopen('ZJ_DIR', v_file_name, 'W');
       
        utl_file.put_line(v_file, PrintDeskbankFile(p_date));
        
        utl_file.fclose(v_file);
    END;
 
    
    PROCEDURE DailySettlement 
    IS    
        v_db_name VARCHAR2(50);
        v_bs_name VARCHAR2(50);
    BEGIN
        -- FIRST, insert transactions that have not been loaded into FSS_DAILY_TRANSACRIONS
        InsertTransactions;
        
        -- SECOND, settle transactions for today and update LOGREF
        SettleTransactions;
        
        DeskbankFile(trunc(sysdate));
    
        v_db_name := '13029285' || '_DS_' || to_char(sysdate, 'DDMMYYYY') || '.dat';
        v_bs_name := '13029285' || '_DSREP_' || to_char(sysdate, 'DDMMYYYY') || '.rpt';
        
        Send_email(EMAIL_TO,
                   EMAIL_FROM,
                   EMAIL_SUBJECT,
                   EMAIL_TEXT_MSG,
                   v_bs_name,
                   PrintSummary(trunc(sysdate), v_bs_name),
                   v_db_name,
                   PrintDeskbankFile(trunc(sysdate)));
        -- THIRD, settle transactions for last month and update LOGREF
--         SettleLastMonthTransactions;
    END;

    PROCEDURE DailyBankingSummary(p_date IN DATE default sysdate) 
    IS
        v_file_name VARCHAR2(50);
        v_file utl_file.file_type;
        
    BEGIN
        v_file_name := '13029285_DSREP_' || to_char(p_date, 'DDMMYYYY') || '.rpt';
        v_file := utl_file.fopen('ZJ_DIR', v_file_name, 'W');
        
        utl_file.put_line(v_file, PrintSummary(p_date, v_file_name));
        
        utl_file.fclose(v_file);
    END;

   
    PROCEDURE FRAUDREPORT
    IS
        v_previous_amount NUMBER:=-1;
        v_previous_nr     NUMBER:=-1;
        cursor c_cardid is 
            select distinct cardid from FSS_DAILY_TRANSACTIONS;
        cursor c_payments(p_cardid VARCHAR2) is
            select * from FSS_DAILY_TRANSACTIONS where cardid=p_cardid order by transactiondate ASC;
    BEGIN
        for r_cardid in c_cardid loop
            v_previous_amount := -1;
            for r_payments in c_payments(r_cardid.cardid) loop
                if v_previous_amount != -1 then
                    if r_payments.cardoldvalue != v_previous_amount then
                        -- report fraud
                        INSERT INTO FSS_ABNORMAL_ACCOUNTS (TRANSACTIONNR)
                        VALUES(r_payments.TRANSACTIONNR);
                        INSERT INTO FSS_ABNORMAL_ACCOUNTS (TRANSACTIONNR)
                        VALUES(v_previous_nr);
                        COMMIT;
                    end if;
                    if r_payments.cardoldvalue - r_payments.transactionamount != r_payments.cardnewvalue then
                        -- report fraud
                        INSERT INTO FSS_ABNORMAL_TRANSACTIONS (TRANSACTIONNR)
                        VALUES(r_payments.TRANSACTIONNR);
                        COMMIT;
                    end if;
                    
                    -- TODO generate report
                    -- TODO avoid duplicate records
                end if;
                v_previous_amount := r_payments.cardnewvalue;
                v_previous_nr     := r_payments.transactionnr;
            end loop;
        end loop;
    END;        
END Pkg_FSS_Settlement;