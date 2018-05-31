CREATE OR REPLACE PACKAGE Pkg_FSS_Settlement
AS
    PROCEDURE DailySettlement;
    
    PROCEDURE DailyBankingSummary(p_date IN DATE DEFAULT sysdate);

--    PROCEDURE FraudReport;
END Pkg_FSS_Settlement;