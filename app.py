"""
Naggiar Production Database - INDE 513 website
------------------------------------------------
A small Flask website on top of the Chapter 7 SQLite database.

Pages
  /                  Dashboard (cell capacity, upcoming runs, key numbers)
  /machines          Search machines; /machines/<id> shows molds and run history
  /runs              Search production runs; /runs/new schedules a new run
  /lots              Material lots with stock left; /lots/new receives a new lot
  /suppliers         Search suppliers (phones and addresses are multivalued)
  /trace             Food-contact traceability: product -> lots, or lot -> products
  /reports           The 12 Chapter 7 queries, run live

The database file (naggiar.db) is created from database.sql the first time
the app starts. Every connection turns foreign keys ON, so the database's own
rules (CHECK, UNIQUE, FOREIGN KEY, triggers) protect every form.
"""
import os
import sqlite3
from datetime import datetime

from flask import Flask, abort, flash, g, redirect, render_template, request, url_for

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.environ.get("DATABASE_PATH", os.path.join(BASE_DIR, "naggiar.db"))
SQL_PATH = os.path.join(BASE_DIR, "database.sql")

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", "inde513-naggiar-demo")

RUN_STATUSES = ["Planned", "InProgress", "Completed", "Cancelled"]
MACHINE_STATUSES = ["Available", "InUse", "UnderMaintenance", "Inactive"]
MOLDING_TYPES = ["Injection", "Blow"]


# ---------------------------------------------------------------------------
# Database helpers
# ---------------------------------------------------------------------------
def build_database():
    """Create (or re-create) naggiar.db from database.sql."""
    tmp_path = DB_PATH + ".tmp"
    if os.path.exists(tmp_path):
        os.remove(tmp_path)
    conn = sqlite3.connect(tmp_path)
    with open(SQL_PATH, encoding="utf-8") as f:
        conn.executescript(f.read())
    conn.close()
    os.replace(tmp_path, DB_PATH)


if not os.path.exists(DB_PATH):
    build_database()


def get_db():
    if "db" not in g:
        g.db = sqlite3.connect(DB_PATH)
        g.db.row_factory = sqlite3.Row
        # Foreign key enforcement must be turned on for every connection.
        g.db.execute("PRAGMA foreign_keys = ON")
    return g.db


@app.teardown_appcontext
def close_db(_error=None):
    db = g.pop("db", None)
    if db is not None:
        db.close()


def query(sql, args=(), one=False):
    rows = get_db().execute(sql, args).fetchall()
    if one:
        return rows[0] if rows else None
    return rows


def friendly_error(err):
    """Turn a SQLite error into a sentence a user can act on."""
    msg = str(err)
    if "UNIQUE constraint failed: MaterialLot.lotNumber" in msg:
        return "This lot number already exists. Every lot needs its own number."
    if "CHECK constraint failed" in msg:
        return f"The database rejected a value that breaks one of its rules ({msg})."
    if "FOREIGN KEY constraint failed" in msg:
        return "This record points to something that does not exist (foreign key rule)."
    if "NOT NULL constraint failed" in msg:
        return f"A required field is empty ({msg})."
    return f"The database refused this record: {msg}"


def to_sql_datetime(value):
    """'2026-11-30T06:00' (HTML datetime-local) -> '2026-11-30 06:00'."""
    try:
        return datetime.strptime(value, "%Y-%m-%dT%H:%M").strftime("%Y-%m-%d %H:%M")
    except (TypeError, ValueError):
        return None


@app.template_filter("num")
def num(value, decimals=0):
    if value is None or value == "":
        return "-"
    try:
        return f"{float(value):,.{decimals}f}"
    except (TypeError, ValueError):
        return value


@app.context_processor
def inject_globals():
    return {"today": datetime.now().strftime("%d %b %Y")}


# ---------------------------------------------------------------------------
# Dashboard
# ---------------------------------------------------------------------------
@app.route("/")
def index():
    stats = {
        "machines": query("SELECT COUNT(*) AS n FROM Machine", one=True)["n"],
        "in_service": query(
            "SELECT COUNT(*) AS n FROM Machine WHERE machineStatus IN ('Available','InUse')",
            one=True)["n"],
        "in_progress": query(
            "SELECT COUNT(*) AS n FROM ProductionRun WHERE runStatus = 'InProgress'",
            one=True)["n"],
        "planned": query(
            "SELECT COUNT(*) AS n FROM ProductionRun WHERE runStatus = 'Planned'",
            one=True)["n"],
        "reject_rate": query(
            """SELECT ROUND(100.0 * SUM(quantityRejected) / SUM(quantityProduced), 2) AS r
               FROM ProductionRun WHERE runStatus = 'Completed'""", one=True)["r"],
    }
    # Q5 from Chapter 7: machines and operators per cell, and places left.
    cells = query("""
        SELECT ProductionCell.cellId, ProductionCell.cellName, ProductionCell.location,
               ProductionCell.cellStatus,
               Lead.firstName || ' ' || Lead.lastName AS leadName,
               COUNT(DISTINCT Machine.machineId) AS machineCount,
               COUNT(DISTINCT Operator.operatorId) AS operatorCount
        FROM ProductionCell
        JOIN Operator AS Lead ON ProductionCell.operatorId = Lead.operatorId
        LEFT OUTER JOIN Machine ON ProductionCell.cellId = Machine.cellId
        LEFT OUTER JOIN Operator ON ProductionCell.cellId = Operator.cellId
        GROUP BY ProductionCell.cellId
        ORDER BY ProductionCell.cellId""")
    # Q4 from Chapter 7, made general: the next planned runs.
    upcoming = query("""
        SELECT ProductionRun.machineId, ProductionRun.runNo, ProductionRun.plannedStart,
               ProductionCell.cellName, Machine.machineName, Product.productName
        FROM ProductionRun
        JOIN Machine ON ProductionRun.machineId = Machine.machineId
        JOIN ProductionCell ON Machine.cellId = ProductionCell.cellId
        JOIN Mold ON ProductionRun.moldId = Mold.moldId
        JOIN Product ON Mold.productId = Product.productId
        WHERE ProductionRun.runStatus IN ('Planned', 'InProgress')
        ORDER BY ProductionRun.plannedStart ASC
        LIMIT 10""")
    return render_template("index.html", stats=stats, cells=cells, upcoming=upcoming)


# ---------------------------------------------------------------------------
# Machines
# ---------------------------------------------------------------------------
@app.route("/machines")
def machines():
    q = request.args.get("q", "").strip()
    mtype = request.args.get("type", "")
    status = request.args.get("status", "")
    cell = request.args.get("cell", "")

    sql = """
        SELECT Machine.*, ProductionCell.cellName,
               (SELECT COUNT(*) FROM MachineMold
                 WHERE MachineMold.machineId = Machine.machineId) AS moldCount,
               (SELECT COUNT(*) FROM ProductionRun
                 WHERE ProductionRun.machineId = Machine.machineId) AS runCount
        FROM Machine
        JOIN ProductionCell ON Machine.cellId = ProductionCell.cellId
        WHERE 1 = 1"""
    args = []
    if q:
        sql += """ AND (Machine.machineName LIKE ? OR Machine.assetTag LIKE ?
                        OR Machine.manufacturer LIKE ? OR Machine.model LIKE ?)"""
        args += [f"%{q}%"] * 4
    if mtype:
        sql += " AND Machine.moldingType = ?"
        args.append(mtype)
    if status:
        sql += " AND Machine.machineStatus = ?"
        args.append(status)
    if cell:
        sql += " AND Machine.cellId = ?"
        args.append(cell)
    sql += " ORDER BY Machine.assetTag"

    return render_template(
        "machines.html", machines=query(sql, args),
        cells=query("SELECT cellId, cellName FROM ProductionCell ORDER BY cellId"),
        statuses=MACHINE_STATUSES, types=MOLDING_TYPES,
        f={"q": q, "type": mtype, "status": status, "cell": cell})


@app.route("/machines/<int:machine_id>")
def machine_detail(machine_id):
    machine = query("""
        SELECT Machine.*, ProductionCell.cellName FROM Machine
        JOIN ProductionCell ON Machine.cellId = ProductionCell.cellId
        WHERE Machine.machineId = ?""", (machine_id,), one=True)
    if machine is None:
        abort(404)
    molds = query("""
        SELECT Mold.*, Product.productName FROM MachineMold
        JOIN Mold ON MachineMold.moldId = Mold.moldId
        JOIN Product ON Mold.productId = Product.productId
        WHERE MachineMold.machineId = ? ORDER BY Mold.moldId""", (machine_id,))
    runs = query("""
        SELECT ProductionRun.*, Product.productName FROM ProductionRun
        JOIN Mold ON ProductionRun.moldId = Mold.moldId
        JOIN Product ON Mold.productId = Product.productId
        WHERE ProductionRun.machineId = ? ORDER BY ProductionRun.runNo""", (machine_id,))
    return render_template("machine_detail.html", m=machine, molds=molds, runs=runs)


# ---------------------------------------------------------------------------
# Production runs
# ---------------------------------------------------------------------------
@app.route("/runs")
def runs():
    status = request.args.get("status", "")
    machine = request.args.get("machine", "")
    date_from = request.args.get("from", "")
    date_to = request.args.get("to", "")
    q = request.args.get("q", "").strip()

    sql = """
        SELECT ProductionRun.*, Machine.machineName, Machine.assetTag,
               Mold.moldName, Product.productName,
               ROUND(100.0 * ProductionRun.quantityRejected
                     / ProductionRun.quantityProduced, 2) AS rejectRate,
               (SELECT group_concat(Operator.firstName || ' ' || Operator.lastName, ', ')
                  FROM OperatorProductionRun
                  JOIN Operator ON OperatorProductionRun.operatorId = Operator.operatorId
                 WHERE OperatorProductionRun.machineId = ProductionRun.machineId
                   AND OperatorProductionRun.runNo = ProductionRun.runNo) AS operators
        FROM ProductionRun
        JOIN Machine ON ProductionRun.machineId = Machine.machineId
        JOIN Mold ON ProductionRun.moldId = Mold.moldId
        JOIN Product ON Mold.productId = Product.productId
        WHERE 1 = 1"""
    args = []
    if status:
        sql += " AND ProductionRun.runStatus = ?"
        args.append(status)
    if machine:
        sql += " AND ProductionRun.machineId = ?"
        args.append(machine)
    if date_from:
        sql += " AND date(ProductionRun.plannedStart) >= ?"
        args.append(date_from)
    if date_to:
        sql += " AND date(ProductionRun.plannedStart) <= ?"
        args.append(date_to)
    if q:
        sql += " AND (Product.productName LIKE ? OR Mold.moldName LIKE ?)"
        args += [f"%{q}%"] * 2
    sql += " ORDER BY ProductionRun.plannedStart DESC"

    return render_template(
        "runs.html", runs=query(sql, args), statuses=RUN_STATUSES,
        machines=query("SELECT machineId, assetTag, machineName FROM Machine ORDER BY assetTag"),
        f={"status": status, "machine": machine, "from": date_from, "to": date_to, "q": q})


def run_form_options():
    """Machine-mold pairs that may be scheduled, and operators who may work."""
    pairs = query("""
        SELECT Machine.machineId, Machine.assetTag, Machine.machineName, Machine.moldingType,
               Machine.clampingForceKN, Mold.moldId, Mold.moldName,
               Mold.requiredClampingForceKN, Product.productName
        FROM MachineMold
        JOIN Machine ON MachineMold.machineId = Machine.machineId
        JOIN Mold ON MachineMold.moldId = Mold.moldId
        JOIN Product ON Mold.productId = Product.productId
        WHERE Machine.machineStatus IN ('Available', 'InUse')
          AND Mold.moldStatus IN ('Available', 'InUse')
          AND Product.productStatus = 'Active'
        ORDER BY Machine.assetTag, Mold.moldId""")
    operators = query("""
        SELECT Operator.operatorId, Operator.firstName, Operator.lastName,
               ProductionCell.cellName,
               group_concat(OperatorCertifiedMoldingType.certifiedMoldingType, ' + ') AS certs
        FROM Operator
        JOIN ProductionCell ON Operator.cellId = ProductionCell.cellId
        LEFT OUTER JOIN OperatorCertifiedMoldingType
            ON Operator.operatorId = OperatorCertifiedMoldingType.operatorId
        WHERE Operator.operatorStatus = 'Active'
        GROUP BY Operator.operatorId
        ORDER BY Operator.cellId, Operator.lastName""")
    return pairs, operators


@app.route("/runs/new", methods=["GET", "POST"])
def run_new():
    pairs, operators = run_form_options()
    form = request.form if request.method == "POST" else {}
    chosen_ops = request.form.getlist("operators") if request.method == "POST" else []

    if request.method == "POST":
        errors = []
        pair = form.get("pair", "")
        start = to_sql_datetime(form.get("plannedStart"))
        end = to_sql_datetime(form.get("plannedEnd"))
        try:
            machine_id, mold_id = (int(x) for x in pair.split("-"))
        except ValueError:
            machine_id = mold_id = None
            errors.append("Choose a machine and mold.")
        if not start or not end:
            errors.append("Give a planned start and a planned end.")
        elif end <= start:
            errors.append("The planned end must be after the planned start.")
        if not chosen_ops:
            errors.append("Assign at least one operator.")

        machine = None
        if machine_id:
            machine = query("SELECT * FROM Machine WHERE machineId = ?", (machine_id,), one=True)
            fits = query("SELECT 1 FROM MachineMold WHERE machineId = ? AND moldId = ?",
                         (machine_id, mold_id), one=True)
            if machine is None or fits is None:
                errors.append("That mold does not fit that machine (MachineMold).")

        # Business rule: a machine cannot run two jobs at the same time.
        if machine and start and end and end > start:
            clash = query("""
                SELECT runNo, plannedStart, plannedEnd FROM ProductionRun
                WHERE machineId = ? AND runStatus <> 'Cancelled'
                  AND plannedStart < ? AND plannedEnd > ?""",
                (machine_id, end, start), one=True)
            if clash:
                errors.append(
                    f"{machine['machineName']} already has run {clash['runNo']} from "
                    f"{clash['plannedStart']} to {clash['plannedEnd']}.")

        # Business rule: every operator must hold the machine's certification.
        if machine:
            for op_id in chosen_ops:
                ok = query("""
                    SELECT 1 FROM OperatorCertifiedMoldingType
                    WHERE operatorId = ? AND certifiedMoldingType = ?""",
                    (op_id, machine["moldingType"]), one=True)
                if not ok:
                    op = query("SELECT firstName, lastName FROM Operator WHERE operatorId = ?",
                               (op_id,), one=True)
                    name = f"{op['firstName']} {op['lastName']}" if op else f"#{op_id}"
                    errors.append(f"{name} is not certified for {machine['moldingType']} molding.")

        if errors:
            for e in errors:
                flash(e, "error")
        else:
            db = get_db()
            try:
                # Weak entity: runNo restarts at 1 on every machine.
                run_no = query("SELECT COALESCE(MAX(runNo), 0) + 1 AS n FROM ProductionRun "
                               "WHERE machineId = ?", (machine_id,), one=True)["n"]
                db.execute("""
                    INSERT INTO ProductionRun (machineId, runNo, plannedStart, plannedEnd, moldId)
                    VALUES (?, ?, ?, ?, ?)""", (machine_id, run_no, start, end, mold_id))
                for op_id in chosen_ops:
                    db.execute("""
                        INSERT INTO OperatorProductionRun (operatorId, machineId, runNo)
                        VALUES (?, ?, ?)""", (op_id, machine_id, run_no))
                db.commit()   # the run and its operators are saved together
                flash(f"Run {run_no} on {machine['machineName']} was scheduled "
                      f"(status Planned).", "success")
                return redirect(url_for("runs", machine=machine_id))
            except sqlite3.Error as err:
                db.rollback()
                flash(friendly_error(err), "error")

    return render_template("run_new.html", pairs=pairs, operators=operators,
                           form=form, chosen_ops=chosen_ops)


# ---------------------------------------------------------------------------
# Material lots
# ---------------------------------------------------------------------------
LOT_SQL = """
    SELECT MaterialLot.*, Material.materialName, Material.resinType,
           Supplier.supplierName,
           COALESCE(SUM(ProductionRunMaterialLot.quantityConsumedKg), 0) AS consumedKg,
           MaterialLot.receivedQtyKg
               - COALESCE(SUM(ProductionRunMaterialLot.quantityConsumedKg), 0) AS remainingKg,
           ROUND(100.0 * COALESCE(SUM(ProductionRunMaterialLot.quantityConsumedKg), 0)
               / MaterialLot.receivedQtyKg, 1) AS percentUsed
    FROM MaterialLot
    JOIN Material ON MaterialLot.materialId = Material.materialId
    JOIN Supplier ON MaterialLot.supplierId = Supplier.supplierId
    LEFT OUTER JOIN ProductionRunMaterialLot
        ON MaterialLot.lotNumber = ProductionRunMaterialLot.lotNumber
"""


@app.route("/lots")
def lots():
    q = request.args.get("q", "").strip()
    material = request.args.get("material", "")
    sql = LOT_SQL + " WHERE 1 = 1"
    args = []
    if q:
        sql += """ AND (MaterialLot.lotNumber LIKE ? OR Material.materialName LIKE ?
                        OR Supplier.supplierName LIKE ?)"""
        args += [f"%{q}%"] * 3
    if material:
        sql += " AND MaterialLot.materialId = ?"
        args.append(material)
    sql += " GROUP BY MaterialLot.lotNumber ORDER BY MaterialLot.receiptDate DESC"
    return render_template(
        "lots.html", lots=query(sql, args),
        materials=query("SELECT materialId, materialName FROM Material ORDER BY materialName"),
        f={"q": q, "material": material})


def food_contact_material(material_id):
    """True if any food-contact product is made with this material."""
    return query("""
        SELECT 1 FROM ProductMaterial
        JOIN Product ON ProductMaterial.productId = Product.productId
        WHERE ProductMaterial.materialId = ? AND Product.foodContactRequired = 'Yes'""",
        (material_id,), one=True) is not None


@app.route("/lots/new", methods=["GET", "POST"])
def lot_new():
    materials = query("""SELECT materialId, materialName, resinType FROM Material
                         WHERE materialStatus = 'Active' ORDER BY materialName""")
    pairs = query("""
        SELECT MaterialSupplier.materialId, Supplier.supplierId, Supplier.supplierName
        FROM MaterialSupplier
        JOIN Supplier ON MaterialSupplier.supplierId = Supplier.supplierId
        WHERE Supplier.supplierStatus = 'Approved'
        ORDER BY Supplier.supplierName""")
    suppliers = query("""SELECT supplierId, supplierName FROM Supplier
                         WHERE supplierStatus = 'Approved' ORDER BY supplierName""")
    form = request.form if request.method == "POST" else {}

    if request.method == "POST":
        errors = []
        lot_number = form.get("lotNumber", "").strip().upper()
        material_id = form.get("materialId", "")
        supplier_id = form.get("supplierId", "")
        doc_ref = form.get("complianceDocRef", "").strip() or None

        if material_id and supplier_id and not query(
                "SELECT 1 FROM MaterialSupplier WHERE materialId = ? AND supplierId = ?",
                (material_id, supplier_id), one=True):
            errors.append("This supplier is not listed as a source of this material "
                          "(MaterialSupplier).")
        if material_id and doc_ref is None and food_contact_material(material_id):
            errors.append("This material goes into food-contact products, so the lot "
                          "needs a compliance document reference.")
        if errors:
            for e in errors:
                flash(e, "error")
        else:
            db = get_db()
            try:
                # CHECK rules in the table test the lot number, date and positive amounts.
                db.execute("""
                    INSERT INTO MaterialLot (lotNumber, receiptDate, receivedQtyKg,
                        unitCostPerKg, complianceDocRef, materialId, supplierId)
                    VALUES (?, ?, ?, ?, ?, ?, ?)""",
                    (lot_number, form.get("receiptDate"), form.get("receivedQtyKg"),
                     form.get("unitCostPerKg"), doc_ref, material_id, supplier_id))
                db.commit()
                flash(f"Lot {lot_number} was received.", "success")
                return redirect(url_for("lots", q=lot_number))
            except sqlite3.Error as err:
                db.rollback()
                flash(friendly_error(err), "error")

    return render_template("lot_new.html", materials=materials, suppliers=suppliers,
                           pairs=pairs, form=form)


# ---------------------------------------------------------------------------
# Suppliers
# ---------------------------------------------------------------------------
@app.route("/suppliers")
def suppliers():
    q = request.args.get("q", "").strip()
    sql = """
        SELECT Supplier.*,
               (SELECT group_concat(phone, ' | ') FROM SupplierPhone
                 WHERE SupplierPhone.supplierId = Supplier.supplierId) AS phones,
               (SELECT group_concat(address, ' | ') FROM SupplierAddress
                 WHERE SupplierAddress.supplierId = Supplier.supplierId) AS addresses,
               (SELECT group_concat(Material.materialName, ', ') FROM MaterialSupplier
                  JOIN Material ON MaterialSupplier.materialId = Material.materialId
                 WHERE MaterialSupplier.supplierId = Supplier.supplierId) AS materials,
               (SELECT COUNT(*) FROM MaterialLot
                 WHERE MaterialLot.supplierId = Supplier.supplierId) AS lotCount
        FROM Supplier WHERE 1 = 1"""
    args = []
    if q:
        sql += """ AND (Supplier.supplierName LIKE ? OR Supplier.email LIKE ?
                   OR Supplier.supplierId IN (SELECT supplierId FROM SupplierAddress
                                              WHERE address LIKE ?)
                   OR Supplier.supplierId IN (SELECT MaterialSupplier.supplierId
                        FROM MaterialSupplier JOIN Material
                          ON MaterialSupplier.materialId = Material.materialId
                        WHERE Material.materialName LIKE ?))"""
        args += [f"%{q}%"] * 4
    sql += " ORDER BY Supplier.supplierName"
    return render_template("suppliers.html", suppliers=query(sql, args), q=q)


# ---------------------------------------------------------------------------
# Traceability
# ---------------------------------------------------------------------------
@app.route("/trace")
def trace():
    product_id = request.args.get("product", "")
    lot_number = request.args.get("lot", "")
    product = forward = preforms = lot = backward = None

    if product_id:
        product = query("SELECT * FROM Product WHERE productId = ?", (product_id,), one=True)
        # Q10 from Chapter 7, for any product: run -> lot -> supplier -> document.
        forward = query("""
            SELECT Machine.machineName, ProductionRun.machineId, ProductionRun.runNo,
                   date(ProductionRun.actualStart) AS runDate, ProductionRun.runStatus,
                   MaterialLot.lotNumber, Material.materialName, Supplier.supplierName,
                   MaterialLot.complianceDocRef, ProductionRunMaterialLot.quantityConsumedKg
            FROM Product
            JOIN Mold ON Product.productId = Mold.productId
            JOIN ProductionRun ON Mold.moldId = ProductionRun.moldId
            JOIN Machine ON ProductionRun.machineId = Machine.machineId
            JOIN ProductionRunMaterialLot
                ON ProductionRun.machineId = ProductionRunMaterialLot.machineId
               AND ProductionRun.runNo = ProductionRunMaterialLot.runNo
            JOIN MaterialLot ON ProductionRunMaterialLot.lotNumber = MaterialLot.lotNumber
            JOIN Material ON MaterialLot.materialId = Material.materialId
            JOIN Supplier ON MaterialLot.supplierId = Supplier.supplierId
            WHERE Product.productId = ?
            ORDER BY ProductionRun.actualStart""", (product_id,))
        # Q9 (recursive UsesPreform): a bottle is blown from a preform.
        preforms = query("""
            SELECT Preform.productId, Preform.productName FROM ProductProduct
            JOIN Product AS Preform ON ProductProduct.preformProductId = Preform.productId
            WHERE ProductProduct.bottleProductId = ?""", (product_id,))

    if lot_number:
        lot = query(LOT_SQL + " WHERE MaterialLot.lotNumber = ? GROUP BY MaterialLot.lotNumber",
                    (lot_number,), one=True)
        # Backward trace (recall): which runs and products used this lot?
        backward = query("""
            SELECT Machine.machineName, ProductionRun.runNo, ProductionRun.runStatus,
                   date(ProductionRun.actualStart) AS runDate, Product.productName,
                   Product.foodContactRequired, ProductionRun.quantityProduced,
                   ProductionRunMaterialLot.quantityConsumedKg
            FROM ProductionRunMaterialLot
            JOIN ProductionRun ON ProductionRunMaterialLot.machineId = ProductionRun.machineId
                              AND ProductionRunMaterialLot.runNo = ProductionRun.runNo
            JOIN Machine ON ProductionRun.machineId = Machine.machineId
            JOIN Mold ON ProductionRun.moldId = Mold.moldId
            JOIN Product ON Mold.productId = Product.productId
            WHERE ProductionRunMaterialLot.lotNumber = ?
            ORDER BY ProductionRun.actualStart""", (lot_number,))

    return render_template(
        "trace.html",
        products=query("SELECT productId, productName FROM Product ORDER BY productName"),
        lots=query("SELECT lotNumber FROM MaterialLot ORDER BY lotNumber"),
        product=product, forward=forward, preforms=preforms, lot=lot, backward=backward,
        f={"product": product_id, "lot": lot_number})


# ---------------------------------------------------------------------------
# Reports: the 12 queries from Chapter 7 (Part C), run live
# ---------------------------------------------------------------------------
REPORTS = [
    ("Q1", "WHERE with AND and IN, ORDER BY",
     "Which injection machines in service have at least 2,500 kN of clamping force?",
     """SELECT assetTag, machineName, machineStatus, clampingForceKN
FROM Machine
WHERE moldingType = 'Injection' AND machineStatus IN ('Available', 'InUse')
  AND clampingForceKN >= 2500
ORDER BY clampingForceKN DESC, assetTag ASC"""),
    ("Q2", "LIKE",
     "Which food-contact products are bottles, heaviest first?",
     """SELECT productName, moldingType, unitWeightG
FROM Product
WHERE productName LIKE '%Bottle%' AND foodContactRequired = 'Yes'
ORDER BY unitWeightG DESC, productName ASC"""),
    ("Q3", "GROUP BY with COUNT and SUM",
     "How many production runs are in each status, and how many parts did they produce?",
     """SELECT runStatus,
       COUNT(*) AS runCount,
       COALESCE(SUM(quantityProduced), 0) AS totalProduced
FROM ProductionRun
GROUP BY runStatus
ORDER BY runCount DESC"""),
    ("Q4", "JOIN of five tables",
     "Which runs are planned for 23 to 29 November 2026, and what will each make?",
     """SELECT ProductionRun.plannedStart, ProductionCell.cellName, Machine.machineName,
       ProductionRun.runNo, Product.productName
FROM ProductionRun
JOIN Machine ON ProductionRun.machineId = Machine.machineId
JOIN ProductionCell ON Machine.cellId = ProductionCell.cellId
JOIN Mold ON ProductionRun.moldId = Mold.moldId
JOIN Product ON Mold.productId = Product.productId
WHERE ProductionRun.runStatus = 'Planned'
  AND ProductionRun.plannedStart BETWEEN '2026-11-23 00:00' AND '2026-11-29 23:59'
ORDER BY ProductionRun.plannedStart ASC, ProductionCell.cellName ASC"""),
    ("Q5", "LEFT OUTER JOIN with GROUP BY",
     "How many machines and operators does each cell have, and how many places are free?",
     """SELECT ProductionCell.cellName,
       COUNT(DISTINCT Machine.machineId) AS machineCount,
       COUNT(DISTINCT Operator.operatorId) AS operatorCount,
       6 - COUNT(DISTINCT Machine.machineId) AS freeMachinePlaces,
       12 - COUNT(DISTINCT Operator.operatorId) AS freeOperatorPlaces
FROM ProductionCell
LEFT OUTER JOIN Machine ON ProductionCell.cellId = Machine.cellId
LEFT OUTER JOIN Operator ON ProductionCell.cellId = Operator.cellId
GROUP BY ProductionCell.cellName
ORDER BY machineCount DESC, ProductionCell.cellName ASC"""),
    ("Q6", "LEFT OUTER JOIN with SUM",
     "How much of each active material lot is left after production?",
     """SELECT MaterialLot.lotNumber, Material.materialName, MaterialLot.receivedQtyKg,
       COALESCE(SUM(ProductionRunMaterialLot.quantityConsumedKg), 0) AS consumedKg,
       MaterialLot.receivedQtyKg
           - COALESCE(SUM(ProductionRunMaterialLot.quantityConsumedKg), 0) AS remainingQtyKg,
       ROUND(100.0 * COALESCE(SUM(ProductionRunMaterialLot.quantityConsumedKg), 0)
           / MaterialLot.receivedQtyKg, 1) AS percentUsed
FROM MaterialLot
JOIN Material ON MaterialLot.materialId = Material.materialId
LEFT OUTER JOIN ProductionRunMaterialLot
    ON MaterialLot.lotNumber = ProductionRunMaterialLot.lotNumber
WHERE Material.materialStatus = 'Active'
GROUP BY MaterialLot.lotNumber, Material.materialName, MaterialLot.receivedQtyKg
ORDER BY percentUsed DESC"""),
    ("Q7", "GROUP BY with HAVING",
     "Which products have a reject rate above 2% in completed runs?",
     """SELECT Product.productName,
       COUNT(*) AS completedRuns,
       SUM(ProductionRun.quantityProduced) AS totalProduced,
       SUM(ProductionRun.quantityRejected) AS totalRejected,
       ROUND(100.0 * SUM(ProductionRun.quantityRejected)
           / SUM(ProductionRun.quantityProduced), 2) AS rejectRatePct
FROM ProductionRun
JOIN Mold ON ProductionRun.moldId = Mold.moldId
JOIN Product ON Mold.productId = Product.productId
WHERE ProductionRun.runStatus = 'Completed'
GROUP BY Product.productName
HAVING 100.0 * SUM(ProductionRun.quantityRejected)
           / SUM(ProductionRun.quantityProduced) > 2
ORDER BY rejectRatePct DESC"""),
    ("Q8", "GROUP BY with HAVING, SUM, MIN and MAX",
     "Which suppliers delivered over 20,000 worth of material in September-November 2026?",
     """SELECT Supplier.supplierName,
       COUNT(*) AS lotCount,
       SUM(MaterialLot.receivedQtyKg) AS totalKg,
       ROUND(SUM(MaterialLot.receivedQtyKg * MaterialLot.unitCostPerKg), 2) AS totalCost,
       MIN(MaterialLot.unitCostPerKg) AS lowestPricePerKg,
       MAX(MaterialLot.unitCostPerKg) AS highestPricePerKg
FROM Supplier
JOIN MaterialLot ON Supplier.supplierId = MaterialLot.supplierId
WHERE MaterialLot.receiptDate BETWEEN '2026-09-01' AND '2026-11-30'
GROUP BY Supplier.supplierName
HAVING SUM(MaterialLot.receivedQtyKg * MaterialLot.unitCostPerKg) > 20000
ORDER BY totalCost DESC"""),
    ("Q9", "JOIN of a table to itself (recursive relationship UsesPreform)",
     "Which preform is each bottle blown from?",
     """SELECT Bottle.productName AS bottle,
       Preform.productName AS preform,
       Bottle.unitWeightG AS bottleWeightG,
       Preform.unitWeightG AS preformWeightG
FROM ProductProduct
JOIN Product AS Bottle ON ProductProduct.bottleProductId = Bottle.productId
JOIN Product AS Preform ON ProductProduct.preformProductId = Preform.productId
ORDER BY Preform.productName ASC, Bottle.productName ASC"""),
    ("Q10", "JOIN of seven tables (food-contact traceability)",
     "Which resin lots, suppliers and compliance documents went into the 32 g PET preform?",
     """SELECT Machine.machineName, ProductionRun.runNo,
       date(ProductionRun.actualStart) AS runDate,
       MaterialLot.lotNumber, Supplier.supplierName, MaterialLot.complianceDocRef,
       ProductionRunMaterialLot.quantityConsumedKg
FROM Product
JOIN Mold ON Product.productId = Mold.productId
JOIN ProductionRun ON Mold.moldId = ProductionRun.moldId
JOIN Machine ON ProductionRun.machineId = Machine.machineId
JOIN ProductionRunMaterialLot
    ON ProductionRun.machineId = ProductionRunMaterialLot.machineId
   AND ProductionRun.runNo = ProductionRunMaterialLot.runNo
JOIN MaterialLot ON ProductionRunMaterialLot.lotNumber = MaterialLot.lotNumber
JOIN Supplier ON MaterialLot.supplierId = Supplier.supplierId
WHERE Product.productName = 'PET Preform 32 g 28mm PCO'
ORDER BY ProductionRun.actualStart ASC"""),
    ("Q11", "Calculated column with a date function",
     "Which machines are 8 or more years old?",
     """SELECT assetTag, machineName, installationDate,
       CAST((julianday('now') - julianday(installationDate)) / 365.25 AS INT)
           AS machineAgeYears,
       machineStatus
FROM Machine
WHERE installationDate <= date('now', '-8 years')
ORDER BY installationDate ASC"""),
    ("Q12", "LEFT OUTER JOIN with IS NULL",
     "Did any operator work on a run without the certification that machine needs?",
     """SELECT Operator.firstName, Operator.lastName, Machine.machineName,
       ProductionRun.runNo, date(ProductionRun.plannedStart) AS runDate,
       Machine.moldingType AS requiredCertification
FROM OperatorProductionRun
JOIN Operator ON OperatorProductionRun.operatorId = Operator.operatorId
JOIN ProductionRun ON OperatorProductionRun.machineId = ProductionRun.machineId
                  AND OperatorProductionRun.runNo = ProductionRun.runNo
JOIN Machine ON ProductionRun.machineId = Machine.machineId
LEFT OUTER JOIN OperatorCertifiedMoldingType
    ON OperatorCertifiedMoldingType.operatorId = Operator.operatorId
   AND OperatorCertifiedMoldingType.certifiedMoldingType = Machine.moldingType
WHERE OperatorCertifiedMoldingType.operatorId IS NULL"""),
]


@app.route("/reports")
def reports():
    results = []
    for code, kind, question, sql in REPORTS:
        cur = get_db().execute(sql)
        columns = [d[0] for d in cur.description]
        results.append({"code": code, "kind": kind, "question": question, "sql": sql,
                        "columns": columns, "rows": cur.fetchall()})
    return render_template("reports.html", results=results)


# ---------------------------------------------------------------------------
# Reset the demo data (rebuilds naggiar.db from database.sql)
# ---------------------------------------------------------------------------
@app.route("/reset", methods=["POST"])
def reset():
    close_db()
    build_database()
    flash("The database was reset to the Chapter 7 sample data.", "success")
    return redirect(url_for("index"))


@app.errorhandler(404)
def not_found(_e):
    return render_template("base.html", not_found=True), 404


if __name__ == "__main__":
    app.run(debug=True, port=int(os.environ.get("PORT", 5000)))
