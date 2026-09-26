/* ============================================================================
   CONTOURA LABS — GYM MANAGEMENT SYSTEM
   SQL Server 2022 — TRIGGERS (03_triggers.sql)
   ----------------------------------------------------------------------------
   - Auto-flag expired memberships
   - Auto-update Member.Status based on membership
   ============================================================================ */

USE GymDB;
GO

/* ------------------------------------------------------------------ */
/* Auto-expire memberships past their EndDate                          */
/* ------------------------------------------------------------------ */

CREATE OR ALTER TRIGGER trg_MemberMemberships_AutoExpire
ON MemberMemberships
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    -- Mark as Expired any rows (just inserted/updated) whose EndDate has passed
    UPDATE mm
       SET mm.Status = 'Expired'
    FROM    MemberMemberships mm
    JOIN    inserted i ON i.MemberMembershipID = mm.MemberMembershipID
    WHERE   mm.Status = 'Active'
      AND   mm.EndDate < CAST(GETDATE() AS DATE);

    -- Update the member status accordingly
    UPDATE m
       SET m.Status = 'Expired'
    FROM    Members m
    JOIN    inserted i ON i.MemberID = m.MemberID
    JOIN    MemberMemberships mm ON mm.MemberMembershipID = i.MemberMembershipID
    WHERE   mm.Status = 'Expired'
      AND   m.Status <> 'Frozen';
END;
GO

/* ------------------------------------------------------------------ */
/* Sanity trigger — prevent setting MembershipPlans IsActive=0 while
   active members are on that plan (warns via RAISERROR)              */
/* ------------------------------------------------------------------ */

CREATE OR ALTER TRIGGER trg_MembershipPlans_DeactivateCheck
ON MembershipPlans
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN MemberMemberships mm ON mm.PlanID = i.PlanID
        WHERE i.IsActive = 0 AND mm.Status = 'Active'
    )
    BEGIN
        -- Soft warning only (not blocking); logged to error but transaction continues
        PRINT 'WARNING: A plan was deactivated while active memberships reference it.';
    END
END;
GO

PRINT 'Triggers created successfully.';
GO
