/* ============================================================================
   CONTOURA LABS — GYM MANAGEMENT SYSTEM
   SQL Server 2022 — SAMPLE DATA (05_sample.sql)
   ----------------------------------------------------------------------------
   - Demo members, memberships, attendance, fees, expenses, equipment,
     inventory, workouts, diet, progress.
   - Run AFTER 04_seed.sql on a fresh database.
   ============================================================================ */

USE GymDB;
GO

/* ------------------------------------------------------------------ */
/* MEMBERS (25 sample members)                                         */
/* ------------------------------------------------------------------ */

SET IDENTITY_INSERT Members ON;
INSERT INTO Members (MemberID, BranchID, Code, FullName, FatherName, Gender, DOB, CNIC, Mobile, WhatsApp, Email, Address, EmergencyContact, Photo, JoiningDate, TrainerID, Height, Weight, MedicalNotes, Status, CreatedBy) VALUES
(1,  1,'M-00001','Hamza Sheikh',         'Sheikh Abdul',  'Male',  '1995-04-12','35201-1111111-1','+92 301 1000001','+92 301 1000001','hamza@example.com',     'House 5, Street A, Gulberg',       '+92 301 9000001', NULL,'2024-01-10', 1, 178.5, 82.0,  NULL,                          'Active',   1),
(2,  1,'M-00002','Ayesha Siddiqui',      'Siddiqui Khan', 'Female','1998-07-23','35201-2222222-2','+92 301 1000002','+92 301 1000002','ayesha@example.com',    'House 12, Street B, Model Town',   '+92 301 9000002', NULL,'2024-01-15', 1, 162.0, 65.0,  NULL,                          'Active',   1),
(3,  1,'M-00003','Bilal Khan',           'Khan Zaman',    'Male',  '1992-11-05','35201-3333333-3','+92 301 1000003','+92 301 1000003','bilal@example.com',     'House 23, Street C, Johar Town',   '+92 301 9000003', NULL,'2024-02-01', 1, 175.0, 88.5,  'Mild asthma',                 'Active',   1),
(4,  1,'M-00004','Sana Malik',           'Malik Tariq',   'Female','2000-03-18','35201-4444444-4','+92 301 1000004','+92 301 1000004','sana@example.com',      'House 34, Street D, Iqbal Town',   '+92 301 9000004', NULL,'2024-02-12', 1, 160.0, 58.0,  NULL,                          'Active',   1),
(5,  1,'M-00005','Usman Ali',            'Ali Akbar',     'Male',  '1990-09-30','35201-5555555-5','+92 301 1000005','+92 301 1000005','usman@example.com',     'House 45, Street E, Cantt',        '+92 301 9000005', NULL,'2024-03-01', 1, 180.0, 95.0,  'Hypertension',                'Active',   1),
(6,  1,'M-00006','Fatima Khan',          'Khan Bahadur',  'Female','1996-12-08','35201-6666666-6','+92 301 1000006','+92 301 1000006','fatima@example.com',    'House 56, Street F, DHA',          '+92 301 9000006', NULL,'2024-03-15', 1, 165.0, 70.0,  NULL,                          'Active',   1),
(7,  1,'M-00007','Ahmed Raza',           'Raza Hasan',    'Male',  '1988-06-22','35201-7777777-7','+92 301 1000007','+92 301 1000007','ahmed@example.com',     'House 67, Street G, Gulberg',      '+92 301 9000007', NULL,'2024-04-05', 1, 172.0, 78.0,  NULL,                          'Active',   1),
(8,  1,'M-00008','Mariam Iqbal',         'Iqbal Lateef',  'Female','1999-01-14','35201-8888888-8','+92 301 1000008','+92 301 1000008','mariam@example.com',    'House 78, Street H, Model Town',   '+92 301 9000008', NULL,'2024-04-20', 1, 168.0, 62.0,  NULL,                          'Active',   1),
(9,  1,'M-00009','Zain Abbas',           'Abbas Ali',     'Male',  '1994-08-19','35201-9999999-9','+92 301 1000009','+92 301 1000009','zain@example.com',      'House 89, Street I, Johar Town',   '+92 301 9000009', NULL,'2024-05-01', 1, 174.0, 85.0,  NULL,                          'Active',   1),
(10, 1,'M-00010','Hira Shah',            'Shahid Shah',   'Female','1997-05-25','35202-1010101-1','+92 301 1000010','+92 301 1000010','hira@example.com',      'House 90, Street J, Iqbal Town',   '+92 301 9000010', NULL,'2024-05-12', 1, 161.0, 60.0,  NULL,                          'Active',   1),
(11, 1,'M-00011','Kamran Aslam',         'Aslam Pervaiz', 'Male',  '1985-02-28','35202-1212121-2','+92 301 1000011','+92 301 1000011','kamran@example.com',    'House 11, Street K, Cantt',        '+92 301 9000011', NULL,'2024-06-01', 1, 176.0, 90.0,  'Diabetic',                    'Active',   1),
(12, 1,'M-00012','Nida Aslam',           'Aslam Yousaf',  'Female','2001-10-03','35202-1313131-3','+92 301 1000012','+92 301 1000012','nida@example.com',      'House 22, Street L, DHA',          '+92 301 9000012', NULL,'2024-06-15', 1, 163.0, 55.0,  NULL,                          'Active',   1),
(13, 1,'M-00013','Fahad Iqbal',          'Iqbal Hasan',   'Male',  '1993-04-17','35202-1414141-4','+92 301 1000013','+92 301 1000013','fahad@example.com',     'House 33, Street M, Gulberg',      '+92 301 9000013', NULL,'2024-07-01', 1, 179.0, 80.0,  NULL,                          'Active',   1),
(14, 1,'M-00014','Sara Yousaf',          'Yousaf Khan',   'Female','1996-09-09','35202-1515151-5','+92 301 1000014','+92 301 1000014','sara@example.com',      'House 44, Street N, Model Town',   '+92 301 9000014', NULL,'2024-07-15', 1, 167.0, 68.0,  NULL,                          'Active',   1),
(15, 1,'M-00015','Talha Mehmood',        'Mehmood Akhtar','Male',  '1991-12-12','35202-1616161-6','+92 301 1000015','+92 301 1000015','talha@example.com',     'House 55, Street O, Johar Town',   '+92 301 9000015', NULL,'2024-08-01', 1, 173.0, 87.0,  NULL,                          'Active',   1),
(16, 1,'M-00016','Areeba Khan',          'Khan Sher',     'Female','1999-03-21','35202-1717171-7','+92 301 1000016','+92 301 1000016','areeba@example.com',    'House 66, Street P, Iqbal Town',   '+92 301 9000016', NULL,'2024-08-15', 1, 164.0, 63.0,  NULL,                          'Active',   1),
(17, 1,'M-00017','Hassan Raza',          'Raza Ali',      'Male',  '1989-07-07','35202-1818181-8','+92 301 1000017','+92 301 1000017','hassan@example.com',    'House 77, Street Q, Cantt',        '+92 301 9000017', NULL,'2024-09-01', 1, 181.0, 92.0,  'Knee surgery 2020',           'Active',   1),
(18, 1,'M-00018','Mahnoor Ali',          'Ali Raza',      'Female','1998-11-29','35202-1919191-9','+92 301 1000018','+92 301 1000018','mahnoor@example.com',   'House 88, Street R, DHA',          '+92 301 9000018', NULL,'2024-09-15', 1, 166.0, 59.0,  NULL,                          'Active',   1),
(19, 1,'M-00019','Adeel Hussain',        'Hussain Ali',   'Male',  '1994-05-16','35202-2020202-0','+92 301 1000019','+92 301 1000019','adeel@example.com',     'House 99, Street S, Gulberg',      '+92 301 9000019', NULL,'2024-10-01', 1, 177.0, 83.0,  NULL,                          'Active',   1),
(20, 1,'M-00020','Zoya Imran',           'Imran Khan',    'Female','2000-08-08','35202-2121212-1','+92 301 1000020','+92 301 1000020','zoya@example.com',      'House 10, Street T, Model Town',   '+92 301 9000020', NULL,'2024-10-15', 1, 162.0, 56.0,  NULL,                          'Active',   1),
-- Expired members (membership ended in past)
(21, 1,'M-00021','Bilal Tariq',          'Tariq Mehmood', 'Male',  '1990-03-03','35202-2222222-2','+92 301 1000021','+92 301 1000021','bilalt@example.com',    'House 21, Street U, Johar Town',   '+92 301 9000021', NULL,'2023-06-01', 1, 175.0, 88.0,  NULL,                          'Expired',  1),
(22, 1,'M-00022','Asma Javed',           'Javed Iqbal',   'Female','1997-06-19','35202-2323232-3','+92 301 1000022','+92 301 1000022','asma@example.com',      'House 32, Street V, Iqbal Town',   '+92 301 9000022', NULL,'2023-07-15', 1, 160.0, 70.0,  NULL,                          'Expired',  1),
(23, 1,'M-00023','Saad Anwar',           'Anwar Ul Haq',  'Male',  '1988-10-25','35202-2424242-4','+92 301 1000023','+92 301 1000023','saad@example.com',      'House 43, Street W, Cantt',        '+92 301 9000023', NULL,'2023-08-01', 1, 178.0, 95.0,  NULL,                          'Expired',  1),
-- Frozen member
(24, 1,'M-00024','Iqra Naveed',          'Naveed Ahmad',  'Female','1999-12-05','35202-2525252-5','+92 301 1000024','+92 301 1000024','iqra@example.com',      'House 54, Street X, DHA',          '+92 301 9000024', NULL,'2024-09-01', 1, 165.0, 64.0,  NULL,                          'Frozen',   1),
-- Inactive member
(25, 1,'M-00025','Omer Farooq',          'Farooq Aziz',   'Male',  '1992-02-14','35202-2626262-6','+92 301 1000025','+92 301 1000025','omer@example.com',      'House 65, Street Y, Gulberg',      '+92 301 9000025', NULL,'2024-01-20', 1, 180.0, 78.0,  NULL,                          'Inactive', 1);
SET IDENTITY_INSERT Members OFF;
GO

/* ------------------------------------------------------------------ */
/* MEMBER MEMBERSHIPS                                                  */
/* ------------------------------------------------------------------ */

SET IDENTITY_INSERT MemberMemberships ON;
INSERT INTO MemberMemberships (MemberMembershipID, MemberID, PlanID, StartDate, EndDate, Status, AmountPaid, Notes, CreatedBy) VALUES
(1,  1, 4, '2024-01-10','2025-01-10','Active',   28000.00, NULL, 4),
(2,  2, 1, '2024-01-15','2024-02-15','Expired',   3000.00, NULL, 4),
(3,  3, 2, '2024-02-01','2024-05-01','Expired',   8000.00, NULL, 4),
(4,  4, 1, '2024-02-12','2024-03-12','Expired',   3000.00, NULL, 4),
(5,  5, 4, '2024-03-01','2025-03-01','Active',   28000.00, NULL, 4),
(6,  6, 3, '2024-03-15','2024-09-15','Active',   15000.00, NULL, 4),
(7,  7, 1, '2024-04-05','2024-05-05','Expired',   3000.00, NULL, 4),
(8,  8, 2, '2024-04-20','2024-07-20','Active',   8000.00, NULL, 4),
(9,  9, 1, '2024-05-01','2024-06-01','Expired',   3000.00, NULL, 4),
(10, 10,1, '2024-05-12','2024-06-12','Expired',   3000.00, NULL, 4),
(11, 11,4, '2024-06-01','2025-06-01','Active',   28000.00, NULL, 4),
(12, 12,1, '2024-06-15','2024-07-15','Expired',   3000.00, NULL, 4),
(13, 13,2, '2024-07-01','2024-10-01','Active',   8000.00, NULL, 4),
(14, 14,1, '2024-07-15','2024-08-15','Expired',   3000.00, NULL, 4),
(15, 15,3, '2024-08-01','2025-02-01','Active',   15000.00, NULL, 4),
(16, 16,1, '2024-08-15','2024-09-15','Expired',   3000.00, NULL, 4),
(17, 17,4, '2024-09-01','2025-09-01','Active',   28000.00, NULL, 4),
(18, 18,1, '2024-09-15','2024-10-15','Expired',   3000.00, NULL, 4),
(19, 19,2, '2024-10-01','2025-01-01','Active',   8000.00, NULL, 4),
(20, 20,1, '2024-10-15','2024-11-15','Expired',   3000.00, NULL, 4),
(21, 21,1, '2023-06-01','2023-07-01','Expired',   3000.00, NULL, 4),
(22, 22,1, '2023-07-15','2023-08-15','Expired',   3000.00, NULL, 4),
(23, 23,2, '2023-08-01','2023-11-01','Expired',   8000.00, NULL, 4),
(24, 24,2, '2024-09-01','2025-02-01','Frozen',    8000.00, NULL, 4),
(25, 25,1, '2024-01-20','2024-02-20','Expired',   3000.00, NULL, 4);
SET IDENTITY_INSERT MemberMemberships OFF;
GO

/* ------------------------------------------------------------------ */
/* INVOICES + FEE COLLECTIONS (last 4 months)                          */
/* ------------------------------------------------------------------ */

SET IDENTITY_INSERT Invoices ON;
INSERT INTO Invoices (InvoiceID, InvoiceNo, MemberID, MemberMembershipID, TotalAmount, Discount, LateFee, Tax, NetAmount, PaidAmount, Status, DueDate, IssueDate, CreatedBy) VALUES
(1, 'INV-202401-0001', 1, 1, 28000.00, 0, 0, 0, 28000.00, 28000.00, 'Paid',     '2024-01-17','2024-01-10', 4),
(2, 'INV-202401-0002', 2, 2, 3000.00,  0, 0, 0, 3000.00,  3000.00,  'Paid',     '2024-01-22','2024-01-15', 4),
(3, 'INV-202402-0001', 3, 3, 8000.00,  0, 0, 0, 8000.00,  8000.00,  'Paid',     '2024-02-08','2024-02-01', 4),
(4, 'INV-202402-0002', 4, 4, 3000.00,  0, 0, 0, 3000.00,  3000.00,  'Paid',     '2024-02-19','2024-02-12', 4),
(5, 'INV-202403-0001', 5, 5, 28000.00, 0, 0, 0, 28000.00, 28000.00, 'Paid',     '2024-03-08','2024-03-01', 4),
(6, 'INV-202403-0002', 6, 6, 15000.00, 0, 0, 0, 15000.00, 15000.00, 'Paid',     '2024-03-22','2024-03-15', 4),
(7, 'INV-202404-0001', 7, 7, 3000.00,  0, 0, 0, 3000.00,  1500.00,  'Partial',  '2024-05-05','2024-04-05', 4),
(8, 'INV-202404-0002', 8, 8, 8000.00,  0, 0, 0, 8000.00,  8000.00,  'Paid',     '2024-04-27','2024-04-20', 4),
(9, 'INV-202405-0001', 9, 9, 3000.00,  0, 0, 0, 3000.00,  0.00,     'Unpaid',   '2024-06-01','2024-05-01', 4),
(10,'INV-202405-0002',10,10, 3000.00,  0, 0, 0, 3000.00,  3000.00,  'Paid',     '2024-05-19','2024-05-12', 4),
(11,'INV-202406-0001',11,11, 28000.00, 0, 0, 0, 28000.00, 28000.00, 'Paid',     '2024-06-08','2024-06-01', 4),
(12,'INV-202406-0002',12,12, 3000.00,  0, 0, 0, 3000.00,  0.00,     'Unpaid',   '2024-07-15','2024-06-15', 4),
(13,'INV-202407-0001',13,13, 8000.00,  0, 0, 0, 8000.00,  8000.00,  'Paid',     '2024-07-08','2024-07-01', 4),
(14,'INV-202407-0002',14,14, 3000.00,  0, 0, 0, 3000.00,  3000.00,  'Paid',     '2024-07-22','2024-07-15', 4),
(15,'INV-202408-0001',15,15, 15000.00, 0, 0, 0, 15000.00, 15000.00, 'Paid',     '2024-08-08','2024-08-01', 4),
(16,'INV-202408-0002',16,16, 3000.00,  0, 0, 0, 3000.00,  0.00,     'Unpaid',   '2024-09-15','2024-08-15', 4),
(17,'INV-202409-0001',17,17, 28000.00, 0, 0, 0, 28000.00, 28000.00, 'Paid',     '2024-09-08','2024-09-01', 4),
(18,'INV-202409-0002',18,18, 3000.00,  0, 0, 0, 3000.00,  3000.00,  'Paid',     '2024-09-22','2024-09-15', 4),
(19,'INV-202410-0001',19,19, 8000.00,  0, 0, 0, 8000.00,  4000.00,  'Partial',  '2024-11-01','2024-10-01', 4),
(20,'INV-202410-0002',20,20, 3000.00,  0, 0, 0, 3000.00,  3000.00,  'Paid',     '2024-10-22','2024-10-15', 4);
SET IDENTITY_INSERT Invoices OFF;
GO

SET IDENTITY_INSERT FeeCollections ON;
INSERT INTO FeeCollections (CollectionID, InvoiceID, MemberID, Amount, MethodID, TransactionRef, CollectedBy, BranchID, CollectedAt, Notes) VALUES
(1,  1, 1, 28000.00, 1, NULL,         4, 1, '2024-01-10 11:20:00', NULL),
(2,  2, 2, 3000.00,  4, 'JC998877',   4, 1, '2024-01-15 14:05:00', NULL),
(3,  3, 3, 8000.00,  2, 'TR-552211',  4, 1, '2024-02-01 10:00:00', NULL),
(4,  4, 4, 3000.00,  1, NULL,         4, 1, '2024-02-12 16:30:00', NULL),
(5,  5, 5, 28000.00, 3, 'CARD-XXXX1234', 4, 1, '2024-03-01 12:15:00', NULL),
(6,  6, 6, 15000.00, 1, NULL,         4, 1, '2024-03-15 09:45:00', NULL),
(7,  7, 7, 1500.00,  1, NULL,         4, 1, '2024-04-05 15:00:00', 'Partial payment'),
(8,  8, 8, 8000.00,  5, 'EP-778899',  4, 1, '2024-04-20 13:20:00', NULL),
(9, 10,10, 3000.00,  1, NULL,         4, 1, '2024-05-12 17:10:00', NULL),
(10,11,11, 28000.00, 2, 'TR-998877',  4, 1, '2024-06-01 11:00:00', NULL),
(11,13,13, 8000.00,  1, NULL,         4, 1, '2024-07-01 14:00:00', NULL),
(12,14,14, 3000.00,  4, 'JC-556677',  4, 1, '2024-07-15 16:30:00', NULL),
(13,15,15, 15000.00, 1, NULL,         4, 1, '2024-08-01 10:00:00', NULL),
(14,17,17, 28000.00, 3, 'CARD-XXXX5678', 4, 1, '2024-09-01 11:45:00', NULL),
(15,18,18, 3000.00,  1, NULL,         4, 1, '2024-09-15 15:30:00', NULL),
(16,19,19, 4000.00,  1, NULL,         4, 1, '2024-10-01 12:00:00', 'Partial payment'),
(17,20,20, 3000.00,  5, 'EP-112233',  4, 1, '2024-10-15 14:30:00', NULL);
SET IDENTITY_INSERT FeeCollections OFF;
GO

/* ------------------------------------------------------------------ */
/* ATTENDANCE — last 14 days, ~15 entries/day                          */
/* ------------------------------------------------------------------ */

-- Build a calendar of last 14 days and assign random member visits
;WITH days AS (
    SELECT TOP (14) DATEADD(DAY, -1 * (ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1), CAST(GETDATE() AS DATE)) AS d
    FROM master..spt_values
),
visitPairs AS (
    SELECT d.d AS CheckDate, m.MemberID
    FROM days d
    CROSS JOIN (VALUES (1),(2),(3),(4),(5),(7),(8),(9),(11),(13),(15),(17),(19),(20)) AS m(MemberID)
)
INSERT INTO Attendance (MemberID, BranchID, CheckInTime, CheckOutTime, Method, CreatedBy)
SELECT  v.MemberID, 1,
        DATEADD(MINUTE, 360 + CAST(RAND(CHECKSUM(NEWID()))*720 AS INT), v.CheckDate),  -- between 6:00 and 18:00
        DATEADD(MINUTE, 540 + CAST(RAND(CHECKSUM(NEWID()))*720 AS INT), v.CheckDate),  -- checkout 9-21h
        'Manual', 4
FROM    visitPairs v;
GO

/* ------------------------------------------------------------------ */
/* EXPENSES — last 4 months                                            */
/* ------------------------------------------------------------------ */

INSERT INTO Expenses (BranchID, Category, Amount, ExpenseDate, Notes, CreatedBy) VALUES
(1, 'Rent',         150000.00, '2024-07-01','Monthly rent — July',          6),
(1, 'Rent',         150000.00, '2024-08-01','Monthly rent — August',        6),
(1, 'Rent',         150000.00, '2024-09-01','Monthly rent — September',     6),
(1, 'Rent',         150000.00, '2024-10-01','Monthly rent — October',       6),
(1, 'Electricity',  45000.00,  '2024-07-05','Electricity bill — July',      6),
(1, 'Electricity',  48000.00,  '2024-08-05','Electricity bill — August',    6),
(1, 'Electricity',  42000.00,  '2024-09-05','Electricity bill — September', 6),
(1, 'Electricity',  46000.00,  '2024-10-05','Electricity bill — October',   6),
(1, 'Internet',     5000.00,   '2024-07-03','Monthly internet',             6),
(1, 'Internet',     5000.00,   '2024-08-03','Monthly internet',             6),
(1, 'Internet',     5000.00,   '2024-09-03','Monthly internet',             6),
(1, 'Internet',     5000.00,   '2024-10-03','Monthly internet',             6),
(1, 'Water',        3000.00,   '2024-07-10','Water bill — July',            6),
(1, 'Water',        3000.00,   '2024-08-10','Water bill — August',          6),
(1, 'Water',        3500.00,   '2024-09-10','Water bill — September',       6),
(1, 'Water',        3000.00,   '2024-10-10','Water bill — October',         6),
(1, 'Maintenance',  12000.00,  '2024-07-18','Treadmill belt replacement',   6),
(1, 'Maintenance',  8000.00,   '2024-08-22','AC servicing',                 6),
(1, 'Maintenance',  15000.00,  '2024-09-12','Cable machine repair',         6),
(1, 'Maintenance',  6000.00,   '2024-10-08','Light fixtures replacement',   6),
(1, 'Misc',         2000.00,   '2024-07-25','Cleaning supplies',            6),
(1, 'Misc',         2500.00,   '2024-08-25','Cleaning supplies',            6),
(1, 'Misc',         1800.00,   '2024-09-25','Cleaning supplies',            6),
(1, 'Misc',         2200.00,   '2024-10-25','Cleaning supplies',            6),
(1, 'Salary',       175000.00, '2024-07-31','Staff salaries — July',        6),
(1, 'Salary',       175000.00, '2024-08-31','Staff salaries — August',      6),
(1, 'Salary',       175000.00, '2024-09-30','Staff salaries — September',   6),
(1, 'Salary',       175000.00, '2024-10-31','Staff salaries — October',     6);
GO

/* ------------------------------------------------------------------ */
/* INCOME RECORDS — supplement fee collections                         */
/* ------------------------------------------------------------------ */

INSERT INTO IncomeRecords (BranchID, CategoryID, Source, Amount, IncomeDate, Notes, CreatedBy) VALUES
(1, 2, 'Personal training — Hamza (5 sessions)', 5000.00, '2024-08-15','PT package', 6),
(1, 2, 'Personal training — Ahmed (10 sessions)', 10000.00, '2024-09-05','PT package', 6),
(1, 3, 'Whey protein sales', 8000.00, '2024-09-20','Supplement sales', 6),
(1, 3, 'Towel + bottle sales', 2500.00, '2024-10-12','Accessories', 6),
(1, 4, 'Locker rental', 1500.00, '2024-10-15','Misc income', 6);
GO

/* ------------------------------------------------------------------ */
/* EQUIPMENT                                                           */
/* ------------------------------------------------------------------ */

SET IDENTITY_INSERT Equipment ON;
INSERT INTO Equipment (EquipmentID, BranchID, Name, Brand, SerialNo, PurchaseDate, PurchasePrice, WarrantyExpiry, Status, Notes, CreatedBy) VALUES
(1, 1, 'Treadmill Pro X1',         'Life Fitness',  'LF-TRE-001',   '2023-01-15', 450000.00, '2026-01-15','Active',     NULL, 1),
(2, 1, 'Treadmill Pro X2',         'Life Fitness',  'LF-TRE-002',   '2023-01-15', 450000.00, '2026-01-15','Active',     NULL, 1),
(3, 1, 'Exercise Bike SB-5',       'Schwinn',       'SW-BIK-005',   '2023-02-10', 180000.00, '2025-02-10','Active',     NULL, 1),
(4, 1, 'Elliptical E7',            'Precor',        'PC-ELP-007',   '2023-02-15', 320000.00, '2025-02-15','Maintenance','Bearing noise', 1),
(5, 1, 'Smith Machine SM-100',     'Body-Solid',    'BS-SMT-100',   '2022-12-01', 380000.00, '2025-12-01','Active',     NULL, 1),
(6, 1, 'Cable Crossover CC-200',   'Body-Solid',    'BS-CC-200',    '2022-12-01', 420000.00, '2025-12-01','Active',     NULL, 1),
(7, 1, 'Leg Press LP-50',          'Hammer Strength','HS-LP-050',   '2023-03-20', 290000.00, '2026-03-20','Active',     NULL, 1),
(8, 1, 'Dumbbells Set 2.5-50kg',   'York',          'YK-DB-SET01',  '2022-11-05', 220000.00, NULL,        'Active',     NULL, 1),
(9, 1, 'Rowing Machine R5',        'Concept2',      'C2-ROW-005',   '2023-04-01', 260000.00, '2026-04-01','Active',     NULL, 1),
(10,1, 'Power Rack PR-1',          'Rogue',         'RG-PR-001',    '2023-04-10', 350000.00, '2026-04-10','Broken',     'Cable snapped, awaiting part', 1);
SET IDENTITY_INSERT Equipment OFF;
GO

INSERT INTO EquipmentMaintenance (EquipmentID, Type, Cost, StartDate, EndDate, Notes, CreatedBy) VALUES
(4, 'Repair',     8000.00, '2024-10-15', NULL,         'Bearing replacement in progress', 6),
(10,'Repair',    15000.00, '2024-10-20', NULL,         'Cable replacement — awaiting part', 6),
(1, 'Routine',    2000.00, '2024-09-01', '2024-09-01', 'Belt inspection',                  6),
(2, 'Routine',    2000.00, '2024-09-01', '2024-09-01', 'Belt inspection',                  6);
GO

/* ------------------------------------------------------------------ */
/* SUPPLIERS + INVENTORY                                               */
/* ------------------------------------------------------------------ */

SET IDENTITY_INSERT Suppliers ON;
INSERT INTO Suppliers (SupplierID, Name, Contact, Phone, Email, Address, IsActive) VALUES
(1, 'Supplement Hub',     'Mr. Adeel',  '+92 42 111 999 888', 'sales@supphub.com',     'Hall Road, Lahore', 1),
(2, 'FitnessGear PK',     'Mr. Kamran', '+92 42 111 777 666', 'info@fitnessgear.pk',   'Anarkali, Lahore',  1),
(3, 'Hydration Nation',   'Ms. Hina',   '+92 42 111 555 444', 'orders@hydrationnat.com','Liberty, Lahore',   1);
SET IDENTITY_INSERT Suppliers OFF;
GO

SET IDENTITY_INSERT InventoryItems ON;
INSERT INTO InventoryItems (ItemID, BranchID, Name, Category, SKU, StockQty, ReorderLevel, SalePrice, PurchasePrice, IsActive, CreatedBy) VALUES
(1, 1, 'Whey Protein 1kg',         'Supplement','WPN-1KG',  20,  5, 4500.00, 3500.00, 1, 1),
(2, 1, 'Creatine 500g',            'Supplement','CRE-500G', 15,  4, 3500.00, 2500.00, 1, 1),
(3, 1, 'BCAA 300g',                'Supplement','BCAA-300', 10,  3, 3000.00, 2000.00, 1, 1),
(4, 1, 'Pre-Workout 250g',         'Supplement','PRE-250G', 8,   3, 4000.00, 3000.00, 1, 1),
(5, 1, 'Energy Drink 250ml',       'Drink',     'ED-250ML', 50, 15, 200.00,  120.00,  1, 1),
(6, 1, 'Bottled Water 1.5L',       'Drink',     'BW-1500ML',100,30, 80.00,   35.00,   1, 1),
(7, 1, 'Gym Gloves',               'Accessory', 'GLV-STD',  12,  5, 1200.00, 600.00,  1, 1),
(8, 1, 'Gym Towel',                'Accessory', 'TWL-STD',  25, 10, 800.00,  400.00,  1, 1);
SET IDENTITY_INSERT InventoryItems OFF;
GO

INSERT INTO InventoryTransactions (ItemID, Type, Qty, UnitPrice, SupplierID, TxnDate, Notes, CreatedBy) VALUES
(1, 'Purchase', 25, 3500.00, 1, '2024-09-01','Quarterly restock', 6),
(1, 'Sale',      5, 4500.00, NULL,'2024-10-01','Walk-in sales',   4),
(5, 'Purchase', 60, 120.00,  3, '2024-09-15','Monthly restock',   6),
(5, 'Sale',     10, 200.00,  NULL,'2024-10-20','Walk-in sales',   4),
(7, 'Purchase', 15, 600.00,  2, '2024-08-20','Stock intake',      6),
(7, 'Sale',      3, 1200.00, NULL,'2024-10-05','Walk-in sales',   4);
GO

/* ------------------------------------------------------------------ */
/* WORKOUT PLAN EXAMPLES                                               */
/* ------------------------------------------------------------------ */

SET IDENTITY_INSERT WorkoutPlans ON;
INSERT INTO WorkoutPlans (PlanID, TrainerID, MemberID, Title, DayOfWeek, StartDate, EndDate, Notes) VALUES
(1, 1, 1, 'Push Day', 'Monday',   '2024-09-01', NULL, 'Chest/Shoulders/Triceps'),
(2, 1, 1, 'Pull Day', 'Tuesday',  '2024-09-01', NULL, 'Back/Biceps'),
(3, 1, 1, 'Leg Day',  'Thursday', '2024-09-01', NULL, 'Quads/Hams/Calves'),
(4, 1, 3, 'Strength Split', 'Daily','2024-08-15', NULL,'Full body strength focus');
SET IDENTITY_INSERT WorkoutPlans OFF;
GO

SET IDENTITY_INSERT WorkoutPlanItems ON;
INSERT INTO WorkoutPlanItems (ItemID, PlanID, Exercise, [Sets], Reps, Weight, RestPeriod, Notes, SortOrder) VALUES
(1, 1, 'Bench Press',     4, '8-10', '60kg', '90s', NULL, 1),
(2, 1, 'Overhead Press',  4, '8-10', '40kg', '90s', NULL, 2),
(3, 1, 'Tricep Pushdown', 3, '12-15','25kg', '60s', NULL, 3),
(4, 2, 'Deadlift',        4, '5',    '100kg','120s',NULL, 1),
(5, 2, 'Pull-ups',        4, '8-10', 'Bodyweight','60s', NULL, 2),
(6, 2, 'Barbell Row',     4, '8-10', '50kg', '90s', NULL, 3),
(7, 3, 'Squat',           5, '5',    '80kg', '120s',NULL, 1),
(8, 3, 'Romanian Deadlift',3,'10',   '60kg', '90s', NULL, 2),
(9, 3, 'Calf Raise',      4, '15',   '40kg', '60s', NULL, 3);
SET IDENTITY_INSERT WorkoutPlanItems OFF;
GO

/* ------------------------------------------------------------------ */
/* DIET PLAN EXAMPLE                                                   */
/* ------------------------------------------------------------------ */

SET IDENTITY_INSERT DietPlans ON;
INSERT INTO DietPlans (PlanID, TrainerID, MemberID, Title, StartDate, EndDate, Notes) VALUES
(1, 1, 1, 'Cutting Diet 2000kcal', '2024-09-01', NULL, 'High protein, low carb');
SET IDENTITY_INSERT DietPlans OFF;
GO

SET IDENTITY_INSERT DietPlanItems ON;
INSERT INTO DietPlanItems (ItemID, PlanID, Meal, Food, Calories, Protein, Carbs, Fat, Notes, SortOrder) VALUES
(1, 1, 'Breakfast', 'Oatmeal + 4 eggs + 1 banana',     550, 30, 65, 15, NULL, 1),
(2, 1, 'Snack',     'Greek yogurt + handful almonds',  250, 20, 15, 10, NULL, 2),
(3, 1, 'Lunch',     'Chicken breast 200g + rice 150g + salad', 650, 50, 70, 12, NULL, 3),
(4, 1, 'Pre-Workout','Apple + black coffee',             100, 1, 25, 0,  NULL, 4),
(5, 1, 'Dinner',    'Grilled fish 200g + sweet potato + veg', 450, 40, 40, 10, NULL, 5);
SET IDENTITY_INSERT DietPlanItems OFF;
GO

/* ------------------------------------------------------------------ */
/* PROGRESS TRACKING                                                   */
/* ------------------------------------------------------------------ */

SET IDENTITY_INSERT ProgressTracking ON;
INSERT INTO ProgressTracking (ProgressID, MemberID, [Date], Weight, BMI, BodyFat, Waist, Chest, Arms, Legs, Notes, CreatedBy) VALUES
(1, 1, '2024-01-15', 85.0, 26.7, 24.0, 95.0, 105.0, 36.0, 60.0, 'Initial assessment', 5),
(2, 1, '2024-03-15', 83.5, 26.2, 22.5, 93.0, 104.0, 36.5, 60.5, 'After 2 months',     5),
(3, 1, '2024-06-15', 82.0, 25.7, 21.0, 91.0, 103.0, 37.0, 61.0, 'Steady progress',    5),
(4, 1, '2024-09-15', 82.0, 25.7, 19.5, 89.0, 102.0, 37.5, 61.5, 'Body recomp',        5),
(5, 3, '2024-02-15', 88.5, 28.9, 26.0, 98.0, 108.0, 37.0, 62.0, 'Initial',            5),
(6, 3, '2024-06-15', 86.0, 28.1, 23.5, 95.0, 106.0, 37.5, 62.5, 'Good progress',      5);
SET IDENTITY_INSERT ProgressTracking OFF;
GO

/* ------------------------------------------------------------------ */
/* NOTIFICATIONS                                                       */
/* ------------------------------------------------------------------ */

INSERT INTO Notifications (Type, Title, Message, UserID, EntityID, IsRead) VALUES
('membership_expiry','Membership Expiring','Member M-00007 (Ahmed Raza) membership expires in 5 days.', 4, 7, 0),
('membership_expiry','Membership Expiring','Member M-00009 (Zain Abbas) membership expires in 3 days.', 4, 9, 0),
('payment_due',      'Payment Due',        'Invoice INV-202405-0001 is unpaid and overdue.',           4, 9, 0),
('payment_due',      'Payment Due',        'Invoice INV-202406-0002 is unpaid and overdue.',           4, 12,0),
('equipment_maintenance','Equipment Maintenance','Treadmill Pro X1 scheduled for routine check.',     3, 1, 1),
('birthday',         'Birthday Today',     'Member M-00013 (Fahad Iqbal) celebrates a birthday today.',4, 13,0);
GO

PRINT 'Sample data inserted successfully.';
GO
