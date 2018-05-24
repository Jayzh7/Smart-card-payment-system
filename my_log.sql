create table my_log (
    log_date DATE,
    log_id   NUMBER,
    message  VARCHAR2(100));


create sequence seq_log_id
start with 1
increment by 1;

create or replace trigger trigger_insert_id
before insert 
on my_log
for each row
begin
select seq_log_id.nextval
into :new.log_id from dual;
end trigger_insert_id;

 
create or replace procedure log_me(p_message varchar)
is
--
PRAGMA AUTONOMOUS_TRANSACTION;
--
begin
insert into my_log(log_date, message) 
values
(sysdate, p_message);
--
commit;
end;
