CREATE OR REPLACE PACKAGE Pkg_FSS_Settlement
AS
    PROCEDURE DailySettlement;
    
    PROCEDURE DailyBankingSummary;

    --PROCEDURE FraudReport;
END Pkg_FSS_Settlement;