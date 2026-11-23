-- Naggiar production database (Chapter 7, Parts A and B).
-- The website runs this file once to create naggiar.db.
-- sqlite3 dot-commands (.mode, .print) were removed so Python can run it.
-- ---------------------------------------------------------------------
-- PART A: create the tables
-- ---------------------------------------------------------------------
-- Foreign key enforcement must be turned on for every connection.
PRAGMA foreign_keys = ON;

-- 1:1 relationship (Leads): operatorId is a foreign key with UNIQUE and NOT NULL.
-- ProductionCell and Operator reference each other, so this foreign key is
-- checked at COMMIT (DEFERRABLE INITIALLY DEFERRED). A cell and its lead
-- operator are then inserted in the same transaction.
CREATE TABLE ProductionCell (
    cellId INTEGER PRIMARY KEY,
    cellName VARCHAR(50) NOT NULL UNIQUE,
    location VARCHAR(100) NOT NULL,
    cellStatus VARCHAR(20) NOT NULL DEFAULT 'Active',
    operatorId INT NOT NULL UNIQUE,
    FOREIGN KEY (operatorId)
        REFERENCES Operator(operatorId)
        DEFERRABLE INITIALLY DEFERRED,
    CHECK (cellId > 0),
    CHECK (length(cellName) BETWEEN 1 AND 50),
    CHECK (length(location) <= 100),
    CHECK (cellStatus IN ('Active', 'Inactive'))
);

-- 1:M relationship (HasAssigned): cellId is a foreign key and may repeat.
CREATE TABLE Operator (
    operatorId INTEGER PRIMARY KEY,
    firstName VARCHAR(50) NOT NULL,
    lastName VARCHAR(50) NOT NULL,
    operatorStatus VARCHAR(20) NOT NULL DEFAULT 'Active',
    cellId INT NOT NULL,
    FOREIGN KEY (cellId)
        REFERENCES ProductionCell(cellId),
    CHECK (operatorId > 0),
    CHECK (length(firstName) <= 50),
    CHECK (length(lastName) <= 50),
    CHECK (operatorStatus IN ('Active', 'OnLeave', 'Inactive'))
);

-- 1:M relationship (Contains): cellId is a foreign key and may repeat.
-- assetTag is the fixed-length CHAR(8) attribute.
CREATE TABLE Machine (
    machineId INTEGER PRIMARY KEY,
    assetTag CHAR(8) NOT NULL UNIQUE,
    machineName VARCHAR(50) NOT NULL,
    moldingType VARCHAR(20) NOT NULL,
    manufacturer VARCHAR(50),
    model VARCHAR(50),
    clampingForceKN DECIMAL(10,2) NOT NULL,
    installationDate DATE,
    machineStatus VARCHAR(20) NOT NULL DEFAULT 'Available',
    cellId INT NOT NULL,
    FOREIGN KEY (cellId)
        REFERENCES ProductionCell(cellId),
    CHECK (machineId > 0),
    CHECK (length(assetTag) = 8),
    CHECK (length(machineName) <= 50),
    CHECK (moldingType IN ('Injection', 'Blow')),
    CHECK (length(manufacturer) <= 50),
    CHECK (length(model) <= 50),
    CHECK (clampingForceKN > 0),
    CHECK (installationDate IS date(installationDate)),
    CHECK (machineStatus IN ('Available', 'InUse', 'UnderMaintenance', 'Inactive'))
);

CREATE TABLE Product (
    productId INTEGER PRIMARY KEY,
    productName VARCHAR(50) NOT NULL,
    moldingType VARCHAR(20) NOT NULL,
    unitWeightG DECIMAL(10,2) NOT NULL,
    foodContactRequired VARCHAR(3) NOT NULL DEFAULT 'No',
    productStatus VARCHAR(20) NOT NULL DEFAULT 'Active',
    CHECK (productId > 0),
    CHECK (length(productName) <= 50),
    CHECK (moldingType IN ('Injection', 'Blow')),
    CHECK (unitWeightG > 0),
    CHECK (foodContactRequired IN ('Yes', 'No')),
    CHECK (productStatus IN ('Active', 'Inactive'))
);

-- 1:M relationship (Produces): productId is a foreign key and may repeat.
-- 3NF (Chapter 6): moldingType was removed; a mold's type comes from its Product.
CREATE TABLE Mold (
    moldId INTEGER PRIMARY KEY,
    moldName VARCHAR(50) NOT NULL,
    requiredClampingForceKN DECIMAL(10,2) NOT NULL,
    cavityCount INT NOT NULL,
    moldStatus VARCHAR(20) NOT NULL DEFAULT 'Available',
    productId INT NOT NULL,
    FOREIGN KEY (productId)
        REFERENCES Product(productId),
    CHECK (moldId > 0),
    CHECK (length(moldName) <= 50),
    CHECK (requiredClampingForceKN > 0),
    CHECK (cavityCount BETWEEN 1 AND 1000),
    CHECK (moldStatus IN ('Available', 'InUse', 'UnderMaintenance', 'Inactive'))
);

CREATE TABLE Material (
    materialId INTEGER PRIMARY KEY,
    materialName VARCHAR(50) NOT NULL,
    resinType VARCHAR(30) NOT NULL,
    grade VARCHAR(40) NOT NULL,
    materialStatus VARCHAR(20) NOT NULL DEFAULT 'Active',
    CHECK (materialId > 0),
    CHECK (length(materialName) <= 50),
    CHECK (length(resinType) <= 30),
    CHECK (length(grade) <= 40),
    CHECK (materialStatus IN ('Active', 'Inactive'))
);

-- email is required; it is not unique, because it is not a secondary key.
CREATE TABLE Supplier (
    supplierId INTEGER PRIMARY KEY,
    supplierName VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL,
    supplierStatus VARCHAR(20) NOT NULL DEFAULT 'Approved',
    CHECK (supplierId > 0),
    CHECK (length(supplierName) <= 100),
    CHECK (length(email) <= 100),
    CHECK (email LIKE '%_@_%._%'),
    CHECK (supplierStatus IN ('Approved', 'Suspended', 'Inactive'))
);

-- 1:M relationships (HasLot, Delivers): materialId and supplierId are foreign keys.
-- lotNumber holds letters and digits only. unitCostPerKg is CURRENCY in the
-- data dictionary; SQLite has no currency type, so it is DECIMAL(10,2).
CREATE TABLE MaterialLot (
    lotNumber VARCHAR(30) NOT NULL PRIMARY KEY,
    receiptDate DATE NOT NULL,
    receivedQtyKg DECIMAL(10,2) NOT NULL,
    unitCostPerKg DECIMAL(10,2) NOT NULL,
    complianceDocRef VARCHAR(100),
    materialId INT NOT NULL,
    supplierId INT NOT NULL,
    FOREIGN KEY (materialId)
        REFERENCES Material(materialId),
    FOREIGN KEY (supplierId)
        REFERENCES Supplier(supplierId),
    CHECK (length(lotNumber) BETWEEN 1 AND 30),
    CHECK (lotNumber NOT GLOB '*[^A-Za-z0-9]*'),
    CHECK (receiptDate IS date(receiptDate)),
    CHECK (receivedQtyKg > 0),
    CHECK (unitCostPerKg > 0),
    CHECK (length(complianceDocRef) <= 100)
);

-- Weak entity (HasRun): the owner's key machineId and runNo form the primary key.
CREATE TABLE ProductionRun (
    machineId INT NOT NULL,
    runNo INT NOT NULL,
    plannedStart DATETIME NOT NULL,
    plannedEnd DATETIME NOT NULL,
    actualStart DATETIME,
    actualEnd DATETIME,
    runStatus VARCHAR(20) NOT NULL DEFAULT 'Planned',
    quantityProduced INT,
    quantityRejected INT,
    moldId INT NOT NULL,
    PRIMARY KEY (machineId, runNo),
    FOREIGN KEY (machineId)
        REFERENCES Machine(machineId),
    FOREIGN KEY (moldId)
        REFERENCES Mold(moldId),
    CHECK (runNo > 0),
    CHECK (plannedStart IS strftime('%Y-%m-%d %H:%M', plannedStart)),
    CHECK (plannedEnd IS strftime('%Y-%m-%d %H:%M', plannedEnd)),
    CHECK (actualStart IS strftime('%Y-%m-%d %H:%M', actualStart)),
    CHECK (actualEnd IS strftime('%Y-%m-%d %H:%M', actualEnd)),
    CHECK (plannedEnd > plannedStart),
    CHECK (actualEnd > actualStart),
    CHECK (runStatus IN ('Planned', 'InProgress', 'Completed', 'Cancelled')),
    CHECK (quantityProduced > 0),
    CHECK (quantityRejected BETWEEN 0 AND quantityProduced)
);

-- M:N relationship (Fits): machineId and moldId form the primary key.
CREATE TABLE MachineMold (
    machineId INT NOT NULL,
    moldId INT NOT NULL,
    PRIMARY KEY (machineId, moldId),
    FOREIGN KEY (machineId)
        REFERENCES Machine(machineId),
    FOREIGN KEY (moldId)
        REFERENCES Mold(moldId)
);

-- M:N relationship (Uses): productId and materialId form the primary key.
CREATE TABLE ProductMaterial (
    productId INT NOT NULL,
    materialId INT NOT NULL,
    compositionPercent DECIMAL(5,2) NOT NULL,
    PRIMARY KEY (productId, materialId),
    FOREIGN KEY (productId)
        REFERENCES Product(productId),
    FOREIGN KEY (materialId)
        REFERENCES Material(materialId),
    CHECK (compositionPercent > 0 AND compositionPercent <= 100)
);

-- M:N relationship (AvailableFrom): materialId and supplierId form the primary key.
CREATE TABLE MaterialSupplier (
    materialId INT NOT NULL,
    supplierId INT NOT NULL,
    PRIMARY KEY (materialId, supplierId),
    FOREIGN KEY (materialId)
        REFERENCES Material(materialId),
    FOREIGN KEY (supplierId)
        REFERENCES Supplier(supplierId)
);

-- M:N relationship (Consumes): machineId, runNo and lotNumber form the primary key.
-- A run is referenced by both columns of its key.
CREATE TABLE ProductionRunMaterialLot (
    machineId INT NOT NULL,
    runNo INT NOT NULL,
    lotNumber VARCHAR(30) NOT NULL,
    quantityConsumedKg DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (machineId, runNo, lotNumber),
    FOREIGN KEY (machineId, runNo)
        REFERENCES ProductionRun(machineId, runNo),
    FOREIGN KEY (lotNumber)
        REFERENCES MaterialLot(lotNumber),
    CHECK (quantityConsumedKg > 0)
);

-- M:N relationship (WorksOn): operatorId, machineId and runNo form the primary key.
CREATE TABLE OperatorProductionRun (
    operatorId INT NOT NULL,
    machineId INT NOT NULL,
    runNo INT NOT NULL,
    PRIMARY KEY (operatorId, machineId, runNo),
    FOREIGN KEY (operatorId)
        REFERENCES Operator(operatorId),
    FOREIGN KEY (machineId, runNo)
        REFERENCES ProductionRun(machineId, runNo)
);

-- Recursive M:N relationship (UsesPreform): both foreign keys reference Product
-- and are named by the role each product plays.
CREATE TABLE ProductProduct (
    bottleProductId INT NOT NULL,
    preformProductId INT NOT NULL,
    PRIMARY KEY (bottleProductId, preformProductId),
    FOREIGN KEY (bottleProductId)
        REFERENCES Product(productId),
    FOREIGN KEY (preformProductId)
        REFERENCES Product(productId),
    CHECK (bottleProductId <> preformProductId)
);

-- Multivalued attribute: the composite key allows several addresses per supplier.
CREATE TABLE SupplierAddress (
    supplierId INT NOT NULL,
    address VARCHAR(200) NOT NULL,
    PRIMARY KEY (supplierId, address),
    FOREIGN KEY (supplierId)
        REFERENCES Supplier(supplierId),
    CHECK (length(address) BETWEEN 1 AND 200)
);

-- Multivalued attribute: the composite key allows several phone numbers per supplier.
CREATE TABLE SupplierPhone (
    supplierId INT NOT NULL,
    phone VARCHAR(17) NOT NULL,
    PRIMARY KEY (supplierId, phone),
    FOREIGN KEY (supplierId)
        REFERENCES Supplier(supplierId),
    CHECK (length(phone) <= 17),
    CHECK (phone LIKE '+%')
);

-- Multivalued attribute: the composite key allows several certifications per operator.
CREATE TABLE OperatorCertifiedMoldingType (
    operatorId INT NOT NULL,
    certifiedMoldingType VARCHAR(20) NOT NULL,
    PRIMARY KEY (operatorId, certifiedMoldingType),
    FOREIGN KEY (operatorId)
        REFERENCES Operator(operatorId),
    CHECK (certifiedMoldingType IN ('Injection', 'Blow'))
);

-- Indexes on the foreign key columns marked Y(Y) in the data dictionary.
-- Primary keys and UNIQUE columns are indexed automatically.
CREATE INDEX idx_operator_cell ON Operator(cellId);
CREATE INDEX idx_machine_cell ON Machine(cellId);
CREATE INDEX idx_mold_product ON Mold(productId);
CREATE INDEX idx_lot_material ON MaterialLot(materialId);
CREATE INDEX idx_lot_supplier ON MaterialLot(supplierId);
CREATE INDEX idx_run_mold ON ProductionRun(moldId);
CREATE INDEX idx_pm_material ON ProductMaterial(materialId);
CREATE INDEX idx_ms_supplier ON MaterialSupplier(supplierId);
CREATE INDEX idx_prml_lot ON ProductionRunMaterialLot(lotNumber);
CREATE INDEX idx_opr_run ON OperatorProductionRun(machineId, runNo);
CREATE INDEX idx_pp_preform ON ProductProduct(preformProductId);

-- Business rules from Chapter 4: a cell holds at most 6 machines and 12 operators.
-- Keys and CHECKs cannot count rows, so triggers enforce these limits.
CREATE TRIGGER trg_cell_max_machines_insert
BEFORE INSERT ON Machine
WHEN (SELECT COUNT(*) FROM Machine WHERE cellId = NEW.cellId) >= 6
BEGIN
    SELECT RAISE(ABORT, 'A production cell can contain at most 6 machines');
END;

CREATE TRIGGER trg_cell_max_machines_update
BEFORE UPDATE OF cellId ON Machine
WHEN (SELECT COUNT(*) FROM Machine WHERE cellId = NEW.cellId) >= 6
 AND NEW.cellId <> OLD.cellId
BEGIN
    SELECT RAISE(ABORT, 'A production cell can contain at most 6 machines');
END;

CREATE TRIGGER trg_cell_max_operators_insert
BEFORE INSERT ON Operator
WHEN (SELECT COUNT(*) FROM Operator WHERE cellId = NEW.cellId) >= 12
BEGIN
    SELECT RAISE(ABORT, 'A production cell can have at most 12 operators');
END;

CREATE TRIGGER trg_cell_max_operators_update
BEFORE UPDATE OF cellId ON Operator
WHEN (SELECT COUNT(*) FROM Operator WHERE cellId = NEW.cellId) >= 12
 AND NEW.cellId <> OLD.cellId
BEGIN
    SELECT RAISE(ABORT, 'A production cell can have at most 12 operators');
END;

-- ---------------------------------------------------------------------
-- PART B: fill the tables with sample data
-- ---------------------------------------------------------------------
PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

-- Lead operators are inserted below, in the same transaction.
INSERT INTO ProductionCell (cellId, cellName, location, cellStatus, operatorId)
VALUES
    (1, 'Preform Cell A', 'Hall 1 - Bay 1', 'Active', 1),
    (2, 'Preform Cell B', 'Hall 1 - Bay 2', 'Active', 6),
    (3, 'Stretch Blow Cell', 'Hall 2 - Bay 1', 'Active', 10),
    (4, 'Closures and Housewares Cell', 'Hall 3 - Bay 1', 'Active', 14),
    (5, 'Extrusion Blow Cell', 'Hall 2 - Bay 3', 'Inactive', 18);

INSERT INTO Operator (operatorId, firstName, lastName, operatorStatus, cellId)
VALUES
    (1, 'Karim', 'Haddad', 'Active', 1),
    (2, 'Rana', 'Khoury', 'Active', 1),
    (3, 'Elie', 'Saade', 'Active', 1),
    (4, 'Maya', 'Azar', 'Active', 1),
    (5, 'Fadi', 'Nassar', 'Inactive', 1),
    (6, 'Joelle', 'Mansour', 'Active', 2),
    (7, 'Tarek', 'Rizk', 'Active', 2),
    (8, 'Nour', 'Fakhoury', 'Active', 2),
    (9, 'Ziad', 'Hayek', 'OnLeave', 2),
    (10, 'Lara', 'Daher', 'Active', 3),
    (11, 'Hadi', 'Saliba', 'Active', 3),
    (12, 'Rita', 'Abboud', 'Active', 3),
    (13, 'Sami', 'Karam', 'Active', 3),
    (14, 'Nadine', 'Chahine', 'Active', 4),
    (15, 'Walid', 'Matar', 'Active', 4),
    (16, 'Carla', 'Najjar', 'Active', 4),
    (17, 'Georges', 'Bou Khalil', 'Inactive', 4),
    (18, 'Ali', 'Hamdan', 'Active', 5),
    (19, 'Christelle', 'Habib', 'Active', 5),
    (20, 'Omar', 'Itani', 'Active', 5);

-- Some operators hold two certifications.
INSERT INTO OperatorCertifiedMoldingType (operatorId, certifiedMoldingType)
VALUES
    (1, 'Injection'),
    (2, 'Injection'),
    (3, 'Injection'),
    (4, 'Injection'),
    (4, 'Blow'),
    (5, 'Injection'),
    (6, 'Injection'),
    (7, 'Injection'),
    (8, 'Injection'),
    (9, 'Injection'),
    (10, 'Blow'),
    (11, 'Blow'),
    (12, 'Blow'),
    (12, 'Injection'),
    (13, 'Injection'),
    (14, 'Injection'),
    (15, 'Injection'),
    (16, 'Injection'),
    (17, 'Injection'),
    (18, 'Blow'),
    (19, 'Blow'),
    (20, 'Blow'),
    (20, 'Injection');

-- Preform Cell A is full: it has 6 machines. InUse = running a job now.
INSERT INTO Machine (machineId, assetTag, machineName, moldingType, manufacturer, model,
    clampingForceKN, installationDate, machineStatus, cellId)
VALUES
    (1, 'INJ-0101', 'Preform Line 1', 'Injection', 'Husky', 'HyPET 300', 3000.00, '2014-05-12', 'InUse', 1),
    (2, 'INJ-0102', 'Preform Line 2', 'Injection', 'Husky', 'HyPET 300', 3000.00, '2016-03-08', 'Available', 1),
    (3, 'INJ-0103', 'Preform Line 3', 'Injection', 'Husky', 'HyPET 225', 2250.00, '2018-09-20', 'Available', 1),
    (4, 'INJ-0104', 'Preform Line 4', 'Injection', 'Netstal', 'PET-Line 2400', 2400.00, '2020-01-15', 'Available', 1),
    (5, 'INJ-0105', 'Preform Line 5', 'Injection', 'Netstal', 'PET-Line 4000', 4000.00, '2023-06-01', 'Available', 1),
    (6, 'INJ-0106', 'Preform Line 6', 'Injection', 'Husky', 'HyPET 120', 1200.00, '2011-11-03', 'UnderMaintenance', 1),
    (7, 'INJ-0201', 'Preform Line 7', 'Injection', 'Engel', 'e-mac 280', 2800.00, '2019-04-22', 'InUse', 2),
    (8, 'INJ-0202', 'Preform Line 8', 'Injection', 'Haitian', 'Jupiter 3300', 3300.00, '2022-08-30', 'Available', 2),
    (9, 'BLW-0301', 'Stretch Blow 1', 'Blow', 'Sidel', 'SBO 8 Universal', 600.00, '2015-02-10', 'Available', 3),
    (10, 'BLW-0302', 'Stretch Blow 2', 'Blow', 'Sidel', 'SBO 10 EvoBlow', 650.00, '2021-07-19', 'InUse', 3),
    (11, 'BLW-0303', 'Stretch Blow 3', 'Blow', 'Krones', 'Contiform 3 Pro', 700.00, NULL, 'Available', 3),
    (12, 'INJ-0401', 'Cap Press 1', 'Injection', 'Engel', 'e-cap 220', 2200.00, '2017-10-05', 'Available', 4),
    (13, 'INJ-0402', 'Housewares Press 1', 'Injection', 'Haitian', 'Mars 3800', 3800.00, '2013-03-27', 'Available', 4),
    (14, 'INJ-0403', 'Housewares Press 2', 'Injection', 'Haitian', 'Mars 1600', 1600.00, '2024-02-12', 'Available', 4),
    (15, 'BLW-0501', 'Extrusion Blow 1', 'Blow', 'Kautex', 'KBS 2-20', 200.00, '2012-06-18', 'UnderMaintenance', 5);

INSERT INTO Product (productId, productName, moldingType, unitWeightG,
    foodContactRequired, productStatus)
VALUES
    (1, 'PET Preform 18.5 g 28mm PCO', 'Injection', 18.50, 'Yes', 'Active'),
    (2, 'PET Preform 32 g 28mm PCO', 'Injection', 32.00, 'Yes', 'Active'),
    (3, 'PET Preform 14 g 28mm PCO', 'Injection', 14.00, 'Yes', 'Active'),
    (4, 'PP Flip-Top Cap 28mm', 'Injection', 2.80, 'Yes', 'Active'),
    (5, '500 mL PET Water Bottle', 'Blow', 18.50, 'Yes', 'Active'),
    (6, '1.5 L PET Water Bottle', 'Blow', 32.00, 'Yes', 'Active'),
    (7, '330 mL PET Water Bottle', 'Blow', 14.00, 'Yes', 'Active'),
    (8, '500 mL PET Juice Bottle', 'Blow', 18.50, 'Yes', 'Active'),
    (9, 'HDPE Detergent Bottle 1 L', 'Blow', 55.00, 'No', 'Active'),
    (10, 'PP Food Container 2 L', 'Injection', 120.00, 'Yes', 'Active'),
    (11, 'HDPE Paint Bucket Lid 5 L', 'Injection', 45.00, 'No', 'Inactive');

-- Each bottle is blown from a preform.
INSERT INTO ProductProduct (bottleProductId, preformProductId)
VALUES
    (5, 1),
    (8, 1),
    (6, 2),
    (7, 3);

INSERT INTO Mold (moldId, moldName, requiredClampingForceKN, cavityCount, moldStatus,
    productId)
VALUES
    (1, 'Preform 18.5 g 48-cavity', 2200.00, 48, 'InUse', 1),
    (2, 'Preform 18.5 g 72-cavity', 2900.00, 72, 'InUse', 1),
    (3, 'Preform 32 g 48-cavity', 2800.00, 48, 'Available', 2),
    (4, 'Preform 14 g 96-cavity', 3800.00, 96, 'Available', 3),
    (5, 'Flip-top cap 28mm 32-cavity', 1800.00, 32, 'Available', 4),
    (6, '500 mL water bottle 8-cavity', 550.00, 8, 'Available', 5),
    (7, '1.5 L water bottle 8-cavity', 600.00, 8, 'InUse', 6),
    (8, '330 mL water bottle 8-cavity', 500.00, 8, 'Available', 7),
    (9, '500 mL juice bottle 8-cavity', 550.00, 8, 'Available', 8),
    (10, 'Detergent bottle 1 L 2-cavity', 180.00, 2, 'Available', 9),
    (11, 'Food container 2 L 4-cavity', 3500.00, 4, 'Available', 10),
    (12, 'Paint bucket lid 5 L 2-cavity', 1500.00, 2, 'Inactive', 11);

-- Which molds fit which machines.
INSERT INTO MachineMold (machineId, moldId)
VALUES
    (1, 1),
    (2, 1),
    (3, 1),
    (4, 1),
    (7, 1),
    (1, 2),
    (2, 2),
    (5, 2),
    (8, 2),
    (5, 3),
    (7, 3),
    (8, 3),
    (5, 4),
    (12, 5),
    (13, 5),
    (9, 6),
    (10, 6),
    (11, 6),
    (10, 7),
    (11, 7),
    (9, 8),
    (10, 8),
    (9, 9),
    (11, 9),
    (15, 10),
    (13, 11),
    (14, 12);

INSERT INTO Material (materialId, materialName, resinType, grade, materialStatus)
VALUES
    (1, 'PET Bottle Resin', 'PET', 'IV 0.80 bottle grade', 'Active'),
    (2, 'PP Homopolymer', 'PP', 'MFI 12 injection grade', 'Active'),
    (3, 'PP Random Copolymer', 'PP', 'MFI 25 clarified grade', 'Active'),
    (4, 'HDPE Blow Resin', 'HDPE', 'MFI 0.3 blow grade', 'Active'),
    (5, 'HDPE Injection Resin', 'HDPE', 'MFI 8 injection grade', 'Active'),
    (6, 'White Masterbatch', 'Masterbatch (PE)', 'TiO2 60 percent', 'Active'),
    (7, 'Blue Masterbatch', 'Masterbatch (PE)', 'Pigment 40 percent', 'Active'),
    (8, 'Recycled PET Flakes', 'rPET', 'Food-grade flakes', 'Inactive');

-- The composition of each product adds up to 100%.
INSERT INTO ProductMaterial (productId, materialId, compositionPercent)
VALUES
    (1, 1, 100.00),
    (2, 1, 100.00),
    (3, 1, 100.00),
    (4, 2, 98.00),
    (4, 6, 2.00),
    (5, 1, 100.00),
    (6, 1, 100.00),
    (7, 1, 100.00),
    (8, 1, 100.00),
    (9, 4, 97.00),
    (9, 7, 3.00),
    (10, 3, 100.00),
    (11, 5, 98.00),
    (11, 6, 2.00);

-- Fictional companies (.example web addresses).
INSERT INTO Supplier (supplierId, supplierName, email, supplierStatus)
VALUES
    (1, 'Gulf Polymers Trading', 'sales@gulfpolymers.example', 'Approved'),
    (2, 'Levant Resin Distribution SAL', 'orders@levantresin.example', 'Approved'),
    (3, 'Anatolia Petrochemicals', 'export@anatoliapetro.example', 'Approved'),
    (4, 'EuroColor Masterbatch', 'info@eurocolor.example', 'Approved'),
    (5, 'Cedar Plastics Supply', 'info@cedarplastics.example', 'Approved'),
    (6, 'Nile Polymer Imports', 'contact@nilepolymer.example', 'Inactive');

INSERT INTO SupplierAddress (supplierId, address)
VALUES
    (1, 'Jebel Ali Free Zone, Dubai, UAE'),
    (1, 'Port of Beirut, Warehouse 12, Beirut, Lebanon'),
    (2, 'Industrial Zone, Zouk Mosbeh, Lebanon'),
    (3, 'Organized Industrial Zone, Gebze, Kocaeli, Turkey'),
    (4, 'Industriestrasse 8, Cologne, Germany'),
    (5, 'Bekaa Industrial Area, Zahle, Lebanon'),
    (5, 'Main Road, Dora, Beirut, Lebanon'),
    (6, '10th of Ramadan City, Egypt');

INSERT INTO SupplierPhone (supplierId, phone)
VALUES
    (1, '+971 4 555 0101'),
    (1, '+961 1 555 012'),
    (2, '+961 9 555 230'),
    (3, '+90 262 555 4410'),
    (4, '+49 221 555 7800'),
    (5, '+961 8 555 640'),
    (5, '+961 3 555 918'),
    (6, '+20 15 555 3300');

INSERT INTO MaterialSupplier (materialId, supplierId)
VALUES
    (1, 1),
    (1, 3),
    (2, 2),
    (2, 3),
    (3, 2),
    (4, 1),
    (4, 5),
    (5, 5),
    (6, 4),
    (7, 4),
    (8, 6);

-- Non-food lots have no compliance document (NULL).
INSERT INTO MaterialLot (lotNumber, receiptDate, receivedQtyKg, unitCostPerKg,
    complianceDocRef, materialId, supplierId)
VALUES
    ('PET2609001', '2026-09-08', 22000.00, 1.18, 'DOC-FC-2026-091', 1, 1),
    ('PET2610001', '2026-10-06', 22000.00, 1.15, 'DOC-FC-2026-104', 1, 3),
    ('PET2611001', '2026-11-03', 24000.00, 1.21, 'DOC-FC-2026-117', 1, 1),
    ('PPH2609001', '2026-09-15', 16000.00, 1.05, 'DOC-FC-2026-095', 2, 2),
    ('PPH2611001', '2026-11-10', 16000.00, 1.09, 'DOC-FC-2026-121', 2, 3),
    ('PPR2610001', '2026-10-20', 8000.00, 1.32, 'DOC-FC-2026-110', 3, 2),
    ('HDB2609001', '2026-09-22', 10000.00, 1.12, NULL, 4, 5),
    ('HDB2611001', '2026-11-12', 10000.00, 1.10, NULL, 4, 1),
    ('HDI2610001', '2026-10-14', 6000.00, 1.08, NULL, 5, 5),
    ('WMB2609001', '2026-09-29', 1000.00, 3.40, 'DOC-FC-2026-099', 6, 4),
    ('BMB2610001', '2026-10-27', 500.00, 3.90, NULL, 7, 4),
    ('RPT2608001', '2026-08-18', 5000.00, 0.85, NULL, 8, 6);

-- runNo restarts at 1 on every machine.
-- Planned and cancelled runs have no actual times or quantities (NULL).
INSERT INTO ProductionRun (machineId, runNo, plannedStart, plannedEnd, actualStart,
    actualEnd, runStatus, quantityProduced, quantityRejected, moldId)
VALUES
    (1, 1, '2026-11-02 06:00', '2026-11-02 18:00', '2026-11-02 06:10', '2026-11-02 17:55', 'Completed', 221760, 1330, 1),
    (1, 2, '2026-11-09 06:00', '2026-11-09 18:00', '2026-11-09 06:05', '2026-11-09 18:20', 'Completed', 316800, 2530, 2),
    (1, 3, '2026-11-21 06:00', '2026-11-21 18:00', '2026-11-21 06:15', NULL, 'InProgress', 150000, 900, 2),
    (1, 4, '2026-11-24 06:00', '2026-11-24 18:00', NULL, NULL, 'Planned', NULL, NULL, 1),
    (2, 1, '2026-11-03 06:00', '2026-11-03 18:00', '2026-11-03 06:00', '2026-11-03 17:40', 'Completed', 224000, 2912, 1),
    (2, 2, '2026-11-12 06:00', '2026-11-12 14:00', NULL, NULL, 'Cancelled', NULL, NULL, 2),
    (2, 3, '2026-11-16 06:00', '2026-11-16 18:00', '2026-11-16 06:20', '2026-11-16 18:10', 'Completed', 306000, 2140, 2),
    (2, 4, '2026-11-25 06:00', '2026-11-25 18:00', NULL, NULL, 'Planned', NULL, NULL, 1),
    (3, 1, '2026-11-04 07:00', '2026-11-04 19:00', '2026-11-04 07:05', '2026-11-04 19:00', 'Completed', 228000, 4560, 1),
    (3, 2, '2026-11-18 07:00', '2026-11-18 19:00', '2026-11-18 07:00', '2026-11-18 18:45', 'Completed', 225600, 3610, 1),
    (3, 3, '2026-11-23 07:00', '2026-11-23 19:00', NULL, NULL, 'Planned', NULL, NULL, 1),
    (4, 1, '2026-11-05 06:00', '2026-11-05 18:00', '2026-11-05 06:30', '2026-11-05 18:00', 'Completed', 220800, 1100, 1),
    (5, 1, '2026-11-06 06:00', '2026-11-06 18:00', '2026-11-06 06:00', '2026-11-06 18:00', 'Completed', 172800, 1040, 3),
    (5, 2, '2026-11-13 06:00', '2026-11-13 18:00', '2026-11-13 06:10', '2026-11-13 17:50', 'Completed', 168000, 1180, 3),
    (5, 3, '2026-11-19 06:00', '2026-11-19 18:00', '2026-11-19 06:00', '2026-11-19 17:30', 'Completed', 496800, 6950, 4),
    (5, 4, '2026-11-26 06:00', '2026-11-26 18:00', NULL, NULL, 'Planned', NULL, NULL, 3),
    (7, 1, '2026-11-10 06:00', '2026-11-10 18:00', '2026-11-10 06:15', '2026-11-10 18:00', 'Completed', 169200, 2710, 3),
    (7, 2, '2026-11-21 06:00', '2026-11-21 18:00', '2026-11-21 06:00', NULL, 'InProgress', 140000, 1200, 1),
    (8, 1, '2026-11-11 06:00', '2026-11-11 18:00', '2026-11-11 06:00', '2026-11-11 18:00', 'Completed', 311000, 2180, 2),
    (8, 2, '2026-11-24 06:00', '2026-11-24 18:00', NULL, NULL, 'Planned', NULL, NULL, 3),
    (9, 1, '2026-11-02 06:00', '2026-11-02 18:00', '2026-11-02 06:00', '2026-11-02 18:00', 'Completed', 168000, 2350, 6),
    (9, 2, '2026-11-09 06:00', '2026-11-09 18:00', '2026-11-09 06:30', '2026-11-09 18:00', 'Completed', 160000, 3680, 8),
    (9, 3, '2026-11-17 06:00', '2026-11-17 18:00', '2026-11-17 06:00', '2026-11-17 17:45', 'Completed', 165000, 1980, 9),
    (9, 4, '2026-11-23 06:00', '2026-11-23 18:00', NULL, NULL, 'Planned', NULL, NULL, 6),
    (10, 1, '2026-11-03 06:00', '2026-11-03 18:00', '2026-11-03 06:00', '2026-11-03 18:00', 'Completed', 144000, 2590, 7),
    (10, 2, '2026-11-10 06:00', '2026-11-10 18:00', '2026-11-10 06:05', '2026-11-10 18:00', 'Completed', 170000, 2040, 6),
    (10, 3, '2026-11-21 06:00', '2026-11-21 18:00', '2026-11-21 06:10', NULL, 'InProgress', 60000, 1100, 7),
    (11, 1, '2026-11-12 06:00', '2026-11-12 18:00', '2026-11-12 06:00', '2026-11-12 18:00', 'Completed', 158000, 1580, 9),
    (11, 2, '2026-11-25 06:00', '2026-11-25 18:00', NULL, NULL, 'Planned', NULL, NULL, 7),
    (12, 1, '2026-11-04 06:00', '2026-11-04 22:00', '2026-11-04 06:00', '2026-11-04 22:00', 'Completed', 460800, 3690, 5),
    (12, 2, '2026-11-14 06:00', '2026-11-14 22:00', '2026-11-14 06:20', '2026-11-14 21:40', 'Completed', 441600, 5300, 5),
    (12, 3, '2026-11-27 06:00', '2026-11-27 22:00', NULL, NULL, 'Planned', NULL, NULL, 5),
    (13, 1, '2026-11-05 06:00', '2026-11-05 18:00', '2026-11-05 06:00', '2026-11-05 18:00', 'Completed', 8640, 260, 11),
    (13, 2, '2026-11-16 06:00', '2026-11-16 18:00', '2026-11-16 06:30', '2026-11-16 18:00', 'Completed', 8280, 210, 11),
    (13, 3, '2026-11-20 06:00', '2026-11-20 18:00', NULL, NULL, 'Cancelled', NULL, NULL, 11),
    (14, 1, '2026-10-22 06:00', '2026-10-22 14:00', '2026-10-22 06:00', '2026-10-22 14:00', 'Completed', 1920, 40, 12),
    (15, 1, '2026-10-28 06:00', '2026-10-28 18:00', '2026-10-28 06:00', '2026-10-28 18:00', 'Completed', 10800, 430, 10),
    (15, 2, '2026-11-06 06:00', '2026-11-06 18:00', '2026-11-06 06:00', '2026-11-06 18:00', 'Completed', 10400, 520, 10);

-- Stretch-blow runs blow preforms, so they consume no resin lots.
INSERT INTO ProductionRunMaterialLot (machineId, runNo, lotNumber, quantityConsumedKg)
VALUES
    (1, 1, 'PET2609001', 4110.00),
    (1, 2, 'PET2609001', 5870.00),
    (1, 3, 'PET2611001', 2780.00),
    (2, 1, 'PET2609001', 4150.00),
    (2, 3, 'PET2610001', 5670.00),
    (3, 1, 'PET2609001', 4230.00),
    (3, 2, 'PET2610001', 4180.00),
    (4, 1, 'PET2609001', 3500.00),
    (4, 1, 'PET2610001', 590.00),
    (5, 1, 'PET2610001', 5540.00),
    (5, 2, 'PET2611001', 5380.00),
    (5, 3, 'PET2611001', 6960.00),
    (7, 1, 'PET2610001', 5420.00),
    (7, 2, 'PET2611001', 2600.00),
    (8, 1, 'PET2611001', 5760.00),
    (12, 1, 'PPH2609001', 1270.00),
    (12, 1, 'WMB2609001', 26.00),
    (12, 2, 'PPH2611001', 1215.00),
    (12, 2, 'WMB2609001', 25.00),
    (13, 1, 'PPR2610001', 1040.00),
    (13, 2, 'PPR2610001', 1000.00),
    (14, 1, 'HDI2610001', 85.00),
    (14, 1, 'WMB2609001', 2.00),
    (15, 1, 'HDB2609001', 580.00),
    (15, 1, 'BMB2610001', 18.00),
    (15, 2, 'HDB2609001', 555.00),
    (15, 2, 'BMB2610001', 17.00);

INSERT INTO OperatorProductionRun (operatorId, machineId, runNo)
VALUES
    (1, 1, 1),
    (2, 1, 1),
    (1, 1, 2),
    (3, 1, 2),
    (2, 1, 3),
    (4, 1, 3),
    (3, 2, 1),
    (2, 2, 3),
    (4, 3, 1),
    (1, 3, 2),
    (3, 4, 1),
    (5, 4, 1),
    (4, 5, 1),
    (2, 5, 2),
    (1, 5, 3),
    (3, 5, 3),
    (6, 7, 1),
    (7, 7, 1),
    (8, 7, 2),
    (9, 8, 1),
    (10, 9, 1),
    (11, 9, 2),
    (13, 9, 2),
    (12, 9, 3),
    (10, 10, 1),
    (11, 10, 1),
    (12, 10, 2),
    (11, 10, 3),
    (10, 11, 1),
    (14, 12, 1),
    (15, 12, 2),
    (16, 13, 1),
    (14, 13, 2),
    (17, 13, 2),
    (15, 14, 1),
    (18, 15, 1),
    (19, 15, 2),
    (20, 15, 2);

COMMIT;
