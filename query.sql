select * from FSS_DAILY_SETTLEMENT where LODGEREF IS NULL;

select * from FSS_MERCHANT;

select * from my_log;
begin
Pkg_FSS_Settlement.DailySettlement;
Pkg_FSS_Settlement.DailyBankingSummary;
end;

select count(DISTINCT(CARDID)) from FSS_DAILY_TRANSACTIONS;
select * from FSS_DAILY_TRANSACTIONS where CARDID = '61022004000002232';

insert into FSS_RUN_TABLE (RUNID, RUNSTART, RUNEND)
            values(0, sysdate, sysdate);
        
select sum(TRANSACTIONAMOUNT) from FSS_DAILY_TRANSACTIONS where LODGEREF = 052620180000025026;
select MAX(RUNEND) from FSS_RUN_TABLE ;