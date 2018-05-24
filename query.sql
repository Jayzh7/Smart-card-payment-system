declare
v_file_name VARCHAR2(20);
v_file  utl_file.file_type;
v_date  VARCHAR2(20) := to_char(sysdate, 'DD-MON-YYYY HH24:MI:SS');
v_col_num NUMBER;
begin 
v_file_name := '13029285_' || to_char(sysdate, 'DDMMYYYY');
select count(*) into v_col_num from FSS_TRANSACTIONS;
v_file := utl_file.fopen('MY_DIR', v_file_name, 'W');
utl_file.put_line(v_file, (LPAD(' ', 30, ' ') || 'Tutorial 7 Question' || LPAD(' ', 30, ' ')));
utl_file.put_line(v_file, 'Date: ' || to_char(sysdate, 'DD-Mon-YYYY') || '' || LPAD('Page 1', 63, ' ') || CHR(10));
utl_file.put_line(v_file, 'This file was created by ' || 'Jay' || CHR(10));
utl_file.put_line(v_file, 'Today there are ' || LPAD(v_col_num, 10, '0') || ' transactions blabla');
utl_file.fclose(v_file);    
end;


select * from FSS_DAILY_SETTLEMENT where LODGEREF IS NULL;